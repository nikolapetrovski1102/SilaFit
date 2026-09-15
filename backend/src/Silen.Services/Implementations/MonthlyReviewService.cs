using Microsoft.Extensions.Options;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IMonthlyReviewService"/>
public sealed class MonthlyReviewService(
    IPlansProvider plansProvider,
    IAnalyticsService analyticsService,
    IAnalyticsProvider analyticsProvider,
    IEmailSender emailSender,
    IMonthlyReviewProvider monthlyReviewProvider,
    IOptions<MonthlyReviewOptions> options,
    IOptions<SmtpOptions> smtpOptions) : IMonthlyReviewService
{
    private const int MaxErrorMessageLength = 1000;

    public Task<ServiceResult<MonthlyReviewSummaryDto>> RunAsync(
        int? year, int? month, string? planCode, bool dryRun, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var period = ResolvePeriod(year, month);
            var effectivePlan = string.IsNullOrWhiteSpace(planCode) ? options.Value.PlanCode : planCode!.Trim();
            var startedAtUtc = DateTime.UtcNow;

            // Email is opt-in at three levels: the batch setting, the caller's dry-run
            // flag, and a configured SMTP host. When any is off we still generate and
            // store every report - the app surfaces it - but mark deliveries 'Generated'
            // so a later run with email enabled still reaches these users.
            var emailsEnabled = options.Value.SendEmails
                && !dryRun
                && !string.IsNullOrWhiteSpace(smtpOptions.Value.Host);

            var run = await monthlyReviewProvider
                .StartRunAsync(period.Year, period.Month, effectivePlan, cancellationToken)
                .ConfigureAwait(false);

            var subscribers = await plansProvider
                .GetActiveSubscribersByPlanCodeAsync(effectivePlan, cancellationToken)
                .ConfigureAwait(false);
            var alreadyEmailed = await monthlyReviewProvider
                .GetEmailedUserIdsAsync(period.Year, period.Month, MonthlyReviewDeliveryKinds.Subscriber, cancellationToken)
                .ConfigureAwait(false);

            var reportsGenerated = 0;
            var emailsSent = 0;
            var skipped = 0;
            var failures = 0;
            var failureDetails = new List<MonthlyReviewFailureDto>();

            foreach (var subscriber in subscribers)
            {
                if (alreadyEmailed.Contains(subscriber.UserId))
                {
                    skipped++;
                    continue;
                }

                if (string.IsNullOrWhiteSpace(subscriber.Email))
                {
                    skipped++;
                    await RecordAsync(
                        run.RunId, subscriber.UserId, period, "Skipped",
                        "No email address on file.", generatedAtUtc: null, emailedAtUtc: null, cancellationToken)
                        .ConfigureAwait(false);
                    continue;
                }

                try
                {
                    var analytics = await analyticsService
                        .GetMonthlyAsync(subscriber.UserId, period.Year, period.Month, refresh: false, cancellationToken)
                        .ConfigureAwait(false);

                    if (!analytics.IsSuccess || analytics.Data is null)
                    {
                        // Too little logged activity for the month is an expected outcome, not a
                        // batch failure. Record it as 'Skipped' so a run full of quiet subscribers
                        // doesn't report failures (and a non-zero exit code) for normal behaviour;
                        // only genuine generation errors count as failures.
                        if (analytics.StatusCode == InsufficientAnalyticsDataException.HttpStatusCode)
                        {
                            skipped++;
                            await RecordAsync(
                                run.RunId, subscriber.UserId, period, "Skipped", analytics.UserMessage,
                                generatedAtUtc: null, emailedAtUtc: null, cancellationToken)
                                .ConfigureAwait(false);
                            continue;
                        }

                        failures++;
                        var reason = analytics.LogMessage ?? "Report generation failed.";
                        failureDetails.Add(new MonthlyReviewFailureDto
                        {
                            UserId = subscriber.UserId,
                            Email = subscriber.Email,
                            Message = reason
                        });
                        await RecordAsync(
                            run.RunId, subscriber.UserId, period, "Failed", reason,
                            generatedAtUtc: null, emailedAtUtc: null, cancellationToken)
                            .ConfigureAwait(false);
                        continue;
                    }

                    var report = analytics.Data;
                    reportsGenerated++;

                    if (!emailsEnabled)
                    {
                        await RecordAsync(
                            run.RunId, subscriber.UserId, period, "Generated", errorMessage: null,
                            generatedAtUtc: report.GeneratedAtUtc, emailedAtUtc: null, cancellationToken)
                            .ConfigureAwait(false);
                        continue;
                    }

                    var subject = MonthlyReviewEmailRenderer.BuildSubject(report);
                    var html = MonthlyReviewEmailRenderer.BuildHtml(subscriber.DisplayName, report);
                    await emailSender.SendAsync(subscriber.Email, subject, html, cancellationToken).ConfigureAwait(false);

                    emailsSent++;
                    await RecordAsync(
                        run.RunId, subscriber.UserId, period, "Emailed", errorMessage: null,
                        generatedAtUtc: report.GeneratedAtUtc, emailedAtUtc: DateTime.UtcNow, cancellationToken)
                        .ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    failures++;
                    failureDetails.Add(new MonthlyReviewFailureDto
                    {
                        UserId = subscriber.UserId,
                        Email = subscriber.Email,
                        Message = ex.Message
                    });
                    await RecordAsync(
                        run.RunId, subscriber.UserId, period, "Failed", ex.Message,
                        generatedAtUtc: null, emailedAtUtc: null, cancellationToken)
                        .ConfigureAwait(false);
                }
            }

            var completedAtUtc = DateTime.UtcNow;
            await monthlyReviewProvider
                .CompleteRunAsync(run.RunId, "Completed", subscribers.Count, reportsGenerated, emailsSent, failures, cancellationToken)
                .ConfigureAwait(false);

            return new MonthlyReviewSummaryDto
            {
                RunId = run.RunId,
                Year = period.Year,
                Month = period.Month,
                PlanCode = effectivePlan,
                Audience = MonthlyReviewAudiences.Subscribers,
                EmailsEnabled = emailsEnabled,
                UsersConsidered = subscribers.Count,
                ReportsGenerated = reportsGenerated,
                EmailsSent = emailsSent,
                Skipped = skipped,
                Failures = failures,
                FailureDetails = failureDetails,
                StartedAtUtc = startedAtUtc,
                CompletedAtUtc = completedAtUtc
            };
        });

    /// <inheritdoc cref="IMonthlyReviewService.RunUpsellAsync"/>
    public Task<ServiceResult<MonthlyReviewSummaryDto>> RunUpsellAsync(
        int? year, int? month, bool dryRun, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var period = ResolvePeriod(year, month);
            var opts = options.Value;
            var startedAtUtc = DateTime.UtcNow;

            // Same three-level email gating as the subscriber pass, with its own switch.
            var emailsEnabled = opts.SendUpsellEmails
                && !dryRun
                && !string.IsNullOrWhiteSpace(smtpOptions.Value.Host);

            var run = await monthlyReviewProvider
                .StartRunAsync(period.Year, period.Month, opts.UpsellAudienceCode, cancellationToken)
                .ConfigureAwait(false);

            var nonSubscribers = await plansProvider
                .GetNonSubscribersAsync(cancellationToken)
                .ConfigureAwait(false);
            var alreadyEmailed = await monthlyReviewProvider
                .GetEmailedUserIdsAsync(period.Year, period.Month, MonthlyReviewDeliveryKinds.Upsell, cancellationToken)
                .ConfigureAwait(false);

            var fromDate = period;
            var toDate = period.AddMonths(1).AddDays(-1);
            var minTrackedUnits = Math.Max(1, opts.UpsellMinTrackedUnits);

            var teasersBuilt = 0;
            var emailsSent = 0;
            var skipped = 0;
            var failures = 0;
            var failureDetails = new List<MonthlyReviewFailureDto>();

            foreach (var user in nonSubscribers)
            {
                if (alreadyEmailed.Contains(user.UserId))
                {
                    skipped++;
                    continue;
                }

                if (string.IsNullOrWhiteSpace(user.Email))
                {
                    skipped++;
                    continue;
                }

                try
                {
                    // Raw snapshot only - deliberately not AnalyticsService.GetMonthlyAsync,
                    // which throws ProUpgradeRequiredException for exactly this audience.
                    // No AI call happens for a teaser, so this costs nothing per recipient.
                    var snapshot = await analyticsProvider
                        .GetPeriodSnapshotAsync(user.UserId, fromDate, toDate, cancellationToken)
                        .ConfigureAwait(false);

                    if (snapshot.CompletedSessions + snapshot.LoggedMealDays < minTrackedUnits)
                    {
                        skipped++;
                        await RecordAsync(
                            run.RunId, user.UserId, period, "Skipped",
                            "Not enough logged activity for a teaser.",
                            generatedAtUtc: null, emailedAtUtc: null, cancellationToken,
                            MonthlyReviewDeliveryKinds.Upsell).ConfigureAwait(false);
                        continue;
                    }

                    teasersBuilt++;

                    if (!emailsEnabled)
                    {
                        await RecordAsync(
                            run.RunId, user.UserId, period, "Generated", errorMessage: null,
                            generatedAtUtc: null, emailedAtUtc: null, cancellationToken,
                            MonthlyReviewDeliveryKinds.Upsell).ConfigureAwait(false);
                        continue;
                    }

                    var subject = MonthlyReviewEmailRenderer.BuildUpsellSubject(period.Year, period.Month);
                    var html = MonthlyReviewEmailRenderer.BuildUpsellHtml(
                        user.DisplayName, snapshot, period.Year, period.Month, opts.UpgradeUrl);
                    await emailSender.SendAsync(user.Email, subject, html, cancellationToken).ConfigureAwait(false);

                    emailsSent++;
                    await RecordAsync(
                        run.RunId, user.UserId, period, "Emailed", errorMessage: null,
                        generatedAtUtc: null, emailedAtUtc: DateTime.UtcNow, cancellationToken,
                        MonthlyReviewDeliveryKinds.Upsell).ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    failures++;
                    failureDetails.Add(new MonthlyReviewFailureDto
                    {
                        UserId = user.UserId,
                        Email = user.Email,
                        Message = ex.Message
                    });
                    await RecordAsync(
                        run.RunId, user.UserId, period, "Failed", ex.Message,
                        generatedAtUtc: null, emailedAtUtc: null, cancellationToken,
                        MonthlyReviewDeliveryKinds.Upsell).ConfigureAwait(false);
                }
            }

            var completedAtUtc = DateTime.UtcNow;
            await monthlyReviewProvider
                .CompleteRunAsync(run.RunId, "Completed", nonSubscribers.Count, teasersBuilt, emailsSent, failures, cancellationToken)
                .ConfigureAwait(false);

            return new MonthlyReviewSummaryDto
            {
                RunId = run.RunId,
                Year = period.Year,
                Month = period.Month,
                PlanCode = opts.UpsellAudienceCode,
                Audience = MonthlyReviewAudiences.NonSubscribers,
                EmailsEnabled = emailsEnabled,
                UsersConsidered = nonSubscribers.Count,
                ReportsGenerated = teasersBuilt,
                EmailsSent = emailsSent,
                Skipped = skipped,
                Failures = failures,
                FailureDetails = failureDetails,
                StartedAtUtc = startedAtUtc,
                CompletedAtUtc = completedAtUtc
            };
        });

    private async Task RecordAsync(
        Guid runId,
        Guid userId,
        DateTime period,
        string status,
        string? errorMessage,
        DateTime? generatedAtUtc,
        DateTime? emailedAtUtc,
        CancellationToken cancellationToken,
        string deliveryKind = MonthlyReviewDeliveryKinds.Subscriber)
    {
        // Audit is best-effort: a transient write failure here must not abort the
        // whole batch. The affected user is simply not marked 'Emailed', so the
        // next run picks them up again.
        try
        {
            await monthlyReviewProvider.RecordDeliveryAsync(
                new MonthlyReviewDeliveryModel
                {
                    RunId = runId,
                    UserId = userId,
                    PeriodYear = period.Year,
                    PeriodMonth = period.Month,
                    Status = status,
                    ErrorMessage = Truncate(errorMessage, MaxErrorMessageLength),
                    GeneratedAtUtc = generatedAtUtc,
                    EmailedAtUtc = emailedAtUtc,
                    DeliveryKind = deliveryKind
                },
                cancellationToken).ConfigureAwait(false);
        }
        catch
        {
            // Intentionally swallowed - see comment above.
        }
    }

    private static DateTime ResolvePeriod(int? year, int? month)
    {
        var today = DateTime.UtcNow.Date;
        if (year is null && month is null)
        {
            return new DateTime(today.Year, today.Month, 1, 0, 0, 0, DateTimeKind.Utc).AddMonths(-1);
        }

        var effectiveYear = year ?? today.Year;
        var effectiveMonth = month ?? today.Month;
        if (effectiveMonth is < 1 or > 12)
        {
            throw new ValidationException($"Invalid month {effectiveMonth}.", "Month must be between 1 and 12.");
        }

        return new DateTime(effectiveYear, effectiveMonth, 1, 0, 0, 0, DateTimeKind.Utc);
    }

    private static string? Truncate(string? value, int maxLength) =>
        value is null || value.Length <= maxLength ? value : value[..maxLength];
}
