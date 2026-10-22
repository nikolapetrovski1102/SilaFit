using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface ISplitsProvider
{
    /// <param name="userId">The caller's id, so private/shared splits are filtered to the
    /// assignments that mention them; null (a guest) sees only the public catalogue.</param>
    Task<List<WorkoutSplitModel>> GetAllAsync(Guid? userId, CancellationToken cancellationToken = default);

    /// <param name="userId">Same visibility filter as <see cref="GetAllAsync"/>; an
    /// invisible split comes back as a null header rather than a readable detail.</param>
    Task<(WorkoutSplitModel? Split, List<SplitDayModel> Days, List<SplitDayExerciseModel> Exercises)> GetDetailAsync(
        Guid splitId, Guid? userId, CancellationToken cancellationToken = default);

    /// <param name="isAutoAssigned">True when the recommender is setting this split
    /// rather than the user - see <see cref="ActiveSplitModel.IsAutoAssigned"/>.</param>
    Task<ActiveSplitModel?> SetActiveAsync(Guid userId, Guid splitId, bool isAutoAssigned = false, CancellationToken cancellationToken = default);

    Task<ActiveSplitModel?> GetActiveAsync(Guid userId, CancellationToken cancellationToken = default);

    /* ----------------------------- user-owned splits ----------------------------- */

    /// <summary>Every split this user has built themselves (usp_UserSplits_GetOwned).</summary>
    Task<List<WorkoutSplitModel>> GetOwnedSplitsAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertUserSplitAsync(UserSplitUpsertRequest request, Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Marks an AI-generated split permanent (usp_UserSplit_Keep) - a no-op, not an
    /// error, when the split isn't AI-generated or is already kept.</summary>
    Task<AdminMutationResultModel> KeepUserSplitAsync(Guid splitId, Guid userId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteUserSplitAsync(Guid splitId, Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Copies an owned split with its days and exercises into a new private split
    /// (usp_UserSplit_Duplicate); EntityId is the copy's id. Tier rules are the caller's job.</summary>
    Task<AdminMutationResultModel> DuplicateUserSplitAsync(Guid splitId, Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Copies one day of an owned split, with its exercises, into the slot right after
    /// it (usp_UserSplitDay_Duplicate); EntityId is the new day's id.</summary>
    Task<AdminMutationResultModel> DuplicateUserSplitDayAsync(Guid splitDayId, Guid userId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertUserSplitDayAsync(UserSplitDayUpsertRequest request, Guid userId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteUserSplitDayAsync(Guid splitDayId, Guid userId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertUserSplitDayExerciseAsync(UserSplitDayExerciseUpsertRequest request, Guid userId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteUserSplitDayExerciseAsync(Guid splitDayExerciseId, Guid userId, CancellationToken cancellationToken = default);
}
