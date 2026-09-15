using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

public interface ISplitService
{
    /// <param name="userId">The caller's id if authenticated (guests included), so the returned
    /// splits carry their goal match flag and person-fit score; null marks every split unmatched.</param>
    Task<ServiceResult<List<WorkoutSplitModel>>> GetAllAsync(Guid? userId, CancellationToken cancellationToken = default);

    /// <param name="userId">The caller's id (guests allowed) so a private/shared split the
    /// user is not assigned to is treated as not found rather than readable.</param>
    Task<ServiceResult<SplitDetailDto>> GetDetailAsync(Guid splitId, Guid? userId, CancellationToken cancellationToken = default);

    Task<ServiceResult<ActiveSplitModel>> ActivateAsync(Guid userId, ActivateSplitRequest request, CancellationToken cancellationToken = default);

    /// <summary>Picks the best-scoring split for a user and activates it, using the same
    /// person-fit scorer as <see cref="GetAllAsync"/> (practical capacity from the days/week,
    /// session length, equipment and activity answers + goal + level fit + category affinity),
    /// so the auto-selected split matches the app's "best for you" pick. Safe to call on every
    /// profile save, not just the first: while the user has never activated a split of their own,
    /// each call re-checks the recommendation against the latest onboarding answers and may switch
    /// the active split; once the user activates one for themselves via <see cref="ActivateAsync"/>,
    /// this becomes a permanent no-op (null Data, still a success result) for that user. Also a
    /// no-op when the profile has no goal yet.</summary>
    Task<ServiceResult<ActiveSplitModel?>> AutoAssignRecommendedAsync(Guid userId, UserProfileModel profile, CancellationToken cancellationToken = default);
}
