using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

/// <summary>
/// Monthly batch that generates the AI progress overview ("what improved",
/// "what to improve", "how to continue") for every active ADVANCED subscriber
/// and emails it to them. Designed to be invoked once a month by a scheduler,
/// and safely re-runnable: reports are cached per user+period and already-emailed
/// users are skipped.
/// </summary>
public interface IMonthlyReviewService
{
    /// <summary>
    /// Runs the batch for the given period. When both <paramref name="year"/> and
    /// <paramref name="month"/> are omitted the previous UTC calendar month is used
    /// (the natural period for a job that runs at the start of a month).
    /// <paramref name="planCode"/> overrides the configured default plan.
    /// <paramref name="dryRun"/> generates and stores reports but sends no email.
    /// </summary>
    Task<ServiceResult<MonthlyReviewSummaryDto>> RunAsync(
        int? year, int? month, string? planCode, bool dryRun, CancellationToken cancellationToken = default);

    /// <summary>
    /// Emails the non-paying audience a stats teaser with an upgrade CTA instead
    /// of the full report. Uses only the raw real-numbers snapshot (no AI
    /// generation), so it is free per recipient and does not give away the paid
    /// report. Independently idempotent from <see cref="RunAsync"/> via the
    /// delivery kind, and gated by MonthlyReview:SendUpsellEmails.
    /// </summary>
    Task<ServiceResult<MonthlyReviewSummaryDto>> RunUpsellAsync(
        int? year, int? month, bool dryRun, CancellationToken cancellationToken = default);
}
