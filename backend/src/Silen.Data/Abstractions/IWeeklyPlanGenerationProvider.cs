using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>
/// Persistence for the weekly AI plan-generation batch: run bookkeeping, the
/// candidate audience, and per-user delivery audit - the weekly counterpart
/// of <see cref="IMonthlyReviewProvider"/>.
/// </summary>
public interface IWeeklyPlanGenerationProvider
{
    Task<WeeklyAiPlanRunModel> StartRunAsync(DateTime weekStartUtc, CancellationToken cancellationToken = default);

    Task CompleteRunAsync(
        Guid runId, string status, int usersConsidered, int plansGenerated, int notificationsSent, int failures,
        CancellationToken cancellationToken = default);

    /// <summary>Ids of users already settled (neither split nor diet generation left 'Failed')
    /// for this week, so a re-run only retries users who didn't finish.</summary>
    Task<HashSet<Guid>> GetProcessedUserIdsAsync(DateTime weekStartUtc, CancellationToken cancellationToken = default);

    Task RecordDeliveryAsync(WeeklyAiPlanDeliveryModel delivery, CancellationToken cancellationToken = default);

    /// <summary>Active ADVANCED subscribers.</summary>
    Task<List<PlanSubscriberModel>> GetCandidateUsersAsync(CancellationToken cancellationToken = default);
}
