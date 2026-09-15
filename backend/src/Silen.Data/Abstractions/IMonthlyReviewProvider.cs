using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>
/// Persistence for the monthly review batch: run bookkeeping, the list of users
/// already emailed for a period (idempotency), and per-user delivery audit.
/// </summary>
public interface IMonthlyReviewProvider
{
    Task<MonthlyReviewRunModel> StartRunAsync(
        int periodYear, int periodMonth, string planCode, CancellationToken cancellationToken = default);

    Task CompleteRunAsync(
        Guid runId, string status, int usersConsidered, int reportsGenerated, int emailsSent, int failures,
        CancellationToken cancellationToken = default);

    /// <summary>Ids of users with an 'Emailed' delivery of the given kind for the period, so a re-run never emails them twice.</summary>
    Task<HashSet<Guid>> GetEmailedUserIdsAsync(
        int periodYear, int periodMonth, string deliveryKind, CancellationToken cancellationToken = default);

    Task RecordDeliveryAsync(MonthlyReviewDeliveryModel delivery, CancellationToken cancellationToken = default);
}
