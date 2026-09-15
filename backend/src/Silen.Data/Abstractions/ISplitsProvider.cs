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
}
