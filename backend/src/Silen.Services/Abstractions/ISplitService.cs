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

    /* ----------------------------- user-owned splits ----------------------------- */

    /// <summary>Every split this user has built themselves via the in-app builder.</summary>
    Task<ServiceResult<List<WorkoutSplitModel>>> GetMySplitsAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Creates a new split (null SplitId) or updates one this user owns. Same
    /// validation ranges as the admin builder (duration 1-14, category/level enum).</summary>
    Task<ServiceResult<AdminWriteResultDto>> CreateOrUpdateMySplitAsync(Guid userId, UserSplitUpsertRequest request, CancellationToken cancellationToken = default);

    /// <summary>Refused while any user has the split active, and refused for a split this user doesn't own.</summary>
    Task<ServiceResult<AdminWriteResultDto>> DeleteMySplitAsync(Guid userId, Guid splitId, CancellationToken cancellationToken = default);

    /// <summary>Marks an AI-generated split as permanent: the next Sunday run creates a fresh
    /// split for this user instead of overwriting this one. A no-op for a split that isn't
    /// AI-generated or is already kept.</summary>
    Task<ServiceResult<AdminWriteResultDto>> KeepMySplitAsync(Guid userId, Guid splitId, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> SaveMySplitDayAsync(Guid userId, UserSplitDayUpsertRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> DeleteMySplitDayAsync(Guid userId, Guid splitDayId, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> SaveMySplitDayExerciseAsync(Guid userId, UserSplitDayExerciseUpsertRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> DeleteMySplitDayExerciseAsync(Guid userId, Guid splitDayExerciseId, CancellationToken cancellationToken = default);
}
