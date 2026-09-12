using System.Text.Json;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IAnalyticsService"/>
public sealed class AnalyticsService(
    IAnalyticsProvider analyticsProvider,
    ISubscriptionGate subscriptionGate,
    IOpenRouterClient openRouterClient) : IAnalyticsService
{
    private const string TemplateKey = "MonthlyAnalytics";

    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };

    // Sent to OpenRouter as response_format.json_schema - field names match AiAnalyticsResultDto's
    // camelCase JSON shape exactly, so the AI's raw JSON deserializes straight into it.
    private static readonly JsonElement ResultSchema = JsonDocument.Parse("""
        {
          "type": "object",
          "properties": {
            "strengths": { "type": "array", "items": { "type": "string" } },
            "improvements": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "area": { "type": "string" },
                  "recommendation": { "type": "string" },
                  "priority": { "type": "string", "enum": ["Low", "Medium", "High"] }
                },
                "required": ["area", "recommendation", "priority"],
                "additionalProperties": false
              }
            },
            "focusForNextMonth": { "type": "string" }
          },
          "required": ["strengths", "improvements", "focusForNextMonth"],
          "additionalProperties": false
        }
        """).RootElement.Clone();

    public Task<ServiceResult<MonthlyAnalyticsDto>> GetMonthlyAsync(
        Guid userId, int? year, int? month, bool refresh, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var today = DateTime.UtcNow.Date;
            var effectiveYear = year ?? today.Year;
            var effectiveMonth = month ?? today.Month;
            if (effectiveMonth is < 1 or > 12)
            {
                throw new ValidationException($"Invalid month {effectiveMonth}.", "Month must be between 1 and 12.");
            }

            if (!await subscriptionGate.HasActiveProAsync(userId, cancellationToken).ConfigureAwait(false))
            {
                throw new ProUpgradeRequiredException($"User {userId} requested AI analytics without an active Pro/Advanced subscription.");
            }

            if (!refresh)
            {
                var cached = await analyticsProvider.GetCachedReportAsync(userId, effectiveYear, effectiveMonth, cancellationToken)
                    .ConfigureAwait(false);
                if (cached is not null)
                {
                    var cachedSnapshot = JsonSerializer.Deserialize<MonthlySnapshotModel>(cached.SnapshotJson, JsonOptions)!;
                    var cachedResult = JsonSerializer.Deserialize<AiAnalyticsResultDto>(cached.ResultJson, JsonOptions)!;
                    return BuildDto(effectiveYear, effectiveMonth, cachedSnapshot, cachedResult, cached.GeneratedAtUtc);
                }
            }

            var fromDate = new DateTime(effectiveYear, effectiveMonth, 1, 0, 0, 0, DateTimeKind.Utc);
            var toDate = fromDate.AddMonths(1).AddDays(-1);

            var snapshot = await analyticsProvider.GetMonthlySnapshotAsync(userId, fromDate, toDate, cancellationToken)
                .ConfigureAwait(false);

            var template = await analyticsProvider.GetPromptTemplateAsync(TemplateKey, cancellationToken).ConfigureAwait(false)
                ?? throw new NotFoundException($"No active '{TemplateKey}' prompt template configured.", "AI insights are temporarily unavailable.");

            var periodLabel = fromDate.ToString("MMMM yyyy");
            var userPrompt = BuildUserPrompt(template.UserPromptTemplate, snapshot, periodLabel);

            var aiJson = await openRouterClient.GenerateJsonAsync(template.SystemPrompt, userPrompt, ResultSchema, cancellationToken)
                .ConfigureAwait(false);
            var aiResult = JsonSerializer.Deserialize<AiAnalyticsResultDto>(aiJson, JsonOptions)
                ?? throw new ConflictException("OpenRouter response failed to deserialize.", "AI insights are temporarily unavailable.");

            var snapshotJson = JsonSerializer.Serialize(snapshot);
            var report = await analyticsProvider
                .SaveReportAsync(userId, effectiveYear, effectiveMonth, snapshotJson, aiJson, cancellationToken)
                .ConfigureAwait(false);

            return BuildDto(effectiveYear, effectiveMonth, snapshot, aiResult, report.GeneratedAtUtc);
        });

    private static string BuildUserPrompt(string template, MonthlySnapshotModel snapshot, string periodLabel) =>
        template
            .Replace("{{DisplayName}}", snapshot.DisplayName)
            .Replace("{{PeriodLabel}}", periodLabel)
            .Replace("{{CompletedSessions}}", snapshot.CompletedSessions.ToString())
            .Replace("{{ScheduledSessions}}", snapshot.ScheduledSessions.ToString())
            .Replace("{{TotalTonnageKg}}", snapshot.TotalTonnageKg.ToString("0.#"))
            .Replace("{{AvgRpe}}", snapshot.AvgRpe.ToString("0.#"))
            .Replace("{{CurrentStreakDays}}", snapshot.CurrentStreakDays.ToString())
            .Replace("{{WeeklyCompliancePercent}}", snapshot.WeeklyCompliancePercent.ToString())
            .Replace("{{WeightTrendSummary}}", BuildWeightTrendSummary(snapshot))
            .Replace("{{NutritionAdherenceSummary}}", BuildNutritionAdherenceSummary(snapshot));

    private static string BuildWeightTrendSummary(MonthlySnapshotModel snapshot)
    {
        if (snapshot.StartWeightKg is not { } start || snapshot.EndWeightKg is not { } end)
        {
            return "No bodyweight logs recorded this period.";
        }

        var delta = end - start;
        var direction = delta switch { > 0 => "up", < 0 => "down", _ => "unchanged at" };
        return $"{start:0.#} kg to {end:0.#} kg ({direction} {Math.Abs(delta):0.#} kg)";
    }

    private static string BuildNutritionAdherenceSummary(MonthlySnapshotModel snapshot)
    {
        if (snapshot.LoggedMealDays == 0)
        {
            return "No nutrition logs recorded this period.";
        }

        var summary = $"{snapshot.LoggedMealDays} of {snapshot.TotalDaysInRange} days logged";
        if (snapshot.AvgCaloriesLogged is { } avgCalories && snapshot.TargetCalories is { } targetCalories)
        {
            summary += $", averaging {avgCalories:0} kcal/day against a {targetCalories} kcal target";
        }

        return summary;
    }

    private static MonthlyAnalyticsDto BuildDto(
        int year, int month, MonthlySnapshotModel snapshot, AiAnalyticsResultDto aiResult, DateTime generatedAtUtc) => new()
    {
        Year = year,
        Month = month,
        Summary = new MonthlyAnalyticsSummaryDto
        {
            CompletedSessions = snapshot.CompletedSessions,
            ScheduledSessions = snapshot.ScheduledSessions,
            TotalTonnageKg = snapshot.TotalTonnageKg,
            AvgRpe = snapshot.AvgRpe,
            CurrentStreakDays = snapshot.CurrentStreakDays,
            WeeklyCompliancePercent = snapshot.WeeklyCompliancePercent,
            StartWeightKg = snapshot.StartWeightKg,
            EndWeightKg = snapshot.EndWeightKg,
            LoggedMealDays = snapshot.LoggedMealDays,
            TotalDaysInRange = snapshot.TotalDaysInRange
        },
        Strengths = aiResult.Strengths,
        Improvements = aiResult.Improvements,
        FocusForNextMonth = aiResult.FocusForNextMonth,
        GeneratedAtUtc = generatedAtUtc
    };
}
