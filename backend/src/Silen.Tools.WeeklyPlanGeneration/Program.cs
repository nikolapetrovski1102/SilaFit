// Weekly AI plan generation batch - see deploy/README.md ("Weekly AI splits & diet plans").
//
// For every active Advanced subscriber, looks at what they actually trained and ate
// last week (AnalyticsProvider.GetPeriodSnapshotAsync) and generates a brand-new custom
// split and diet plan for the upcoming week, written into the same user-owned tables the
// manual "My Splits"/"My Diet Plans" builder uses. The model may recommend keeping the
// user's current split (no training change); the diet plan always covers Monday-Sunday
// with breakfast/lunch/dinner/snack and carries a week-long shopping list built from the
// meals' stored ingredients. The plans are left inactive so the user chooses whether to
// activate the new one or keep their current plan.
//
// Idempotent: a user already recorded in WeeklyAiPlanDeliveries for the target week is
// skipped, so re-running (or an overlapping run) is harmless.
//
// Intended to be scheduled once a week (deploy.sh installs a cron entry that runs it
// every Sunday). Can also be run by hand for testing or a backfill.
//
// Usage:
//   ConnectionStrings__SilenDb="..." Encryption__MasterKeyBase64="<base64>" \
//   OpenRouter__ApiKey="..." Smtp__Host="smtp.example.com" \
//     dotnet run --project backend/src/Silen.Tools.WeeklyPlanGeneration
//
// Flags (all optional):
//   --week-start=2026-09-14   Monday of the ISO week to process (default: the week that just ended)
//   --user=<guid>             only process one candidate (handy for testing)
//   --dry-run                 run the full pipeline, write nothing, send nothing
//
// Exit codes: 0 = all processed, 1 = the run failed outright, 2 = completed with per-user failures.

using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Silen.Common.Dtos;
using Silen.Common.Options;
using Silen.Data;
using Silen.Services;
using Silen.Services.Abstractions;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.Configure<OpenRouterOptions>(builder.Configuration.GetSection(OpenRouterOptions.SectionName));
builder.Services.Configure<SmtpOptions>(builder.Configuration.GetSection(SmtpOptions.SectionName));
builder.Services.Configure<EncryptionOptions>(builder.Configuration.GetSection(EncryptionOptions.SectionName));
builder.Services.Configure<PushNotificationOptions>(builder.Configuration.GetSection(PushNotificationOptions.SectionName));
builder.Services.Configure<WeeklyPlanGenerationOptions>(builder.Configuration.GetSection(WeeklyPlanGenerationOptions.SectionName));

builder.Services.AddSilenData();
builder.Services.AddSilenServices();

var weekStart = ParseDate(ArgValue(args, "week-start"));
var onlyUser = ParseGuid(ArgValue(args, "user"));
var dryRun = HasFlag(args, "dry-run");

using var cancellation = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    cancellation.Cancel();
};

using var host = builder.Build();
using var scope = host.Services.CreateScope();
var generationService = scope.ServiceProvider.GetRequiredService<IWeeklyPlanGenerationService>();

Console.WriteLine(
    $"Weekly AI plan generation starting (weekStart={weekStart?.ToString("yyyy-MM-dd") ?? "current ISO week"}, " +
    $"user={onlyUser?.ToString() ?? "all"}, dryRun={dryRun}).");

var result = await generationService.RunAsync(weekStart, dryRun, onlyUser, cancellation.Token);
if (!result.IsSuccess || result.Data is null)
{
    Console.Error.WriteLine($"Weekly AI plan generation failed: {result.LogMessage ?? result.UserMessage}");
    return 1;
}

var summary = result.Data;
Console.WriteLine(JsonSerializer.Serialize(summary, new JsonSerializerOptions { WriteIndented = true }));
Console.WriteLine(
    $"Week {summary.WeekStartUtc:yyyy-MM-dd}: considered {summary.UsersConsidered}, generated {summary.PlansGenerated}, " +
    $"notified {summary.NotificationsSent}, skipped {summary.Skipped}, failed {summary.Failures}.");

foreach (var failure in summary.FailureDetails)
{
    Console.Error.WriteLine($"  FAILED {failure.UserId} ({failure.Email ?? "no email"}): {failure.Message}");
}

return summary.Failures > 0 ? 2 : 0;

static string? ArgValue(string[] args, string name)
{
    var prefix = $"--{name}=";
    for (var i = 0; i < args.Length; i++)
    {
        if (args[i].StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            return args[i][prefix.Length..];
        }

        if (string.Equals(args[i], $"--{name}", StringComparison.OrdinalIgnoreCase)
            && i + 1 < args.Length
            && !args[i + 1].StartsWith("--", StringComparison.Ordinal))
        {
            return args[i + 1];
        }
    }

    return null;
}

static bool HasFlag(string[] args, string name) =>
    args.Any(a => string.Equals(a, $"--{name}", StringComparison.OrdinalIgnoreCase)
                  || a.StartsWith($"--{name}=", StringComparison.OrdinalIgnoreCase));

static Guid? ParseGuid(string? value) => Guid.TryParse(value, out var parsed) ? parsed : null;

static DateTime? ParseDate(string? value) =>
    DateTime.TryParse(value, null, System.Globalization.DateTimeStyles.None, out var parsed)
        ? DateTime.SpecifyKind(parsed.Date, DateTimeKind.Utc)
        : null;
