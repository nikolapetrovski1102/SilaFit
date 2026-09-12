using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface ISplitsProvider
{
    Task<List<WorkoutSplitModel>> GetAllAsync(CancellationToken cancellationToken = default);

    Task<(WorkoutSplitModel? Split, List<SplitDayModel> Days, List<SplitDayExerciseModel> Exercises)> GetDetailAsync(
        Guid splitId, CancellationToken cancellationToken = default);

    Task<ActiveSplitModel?> SetActiveAsync(Guid userId, Guid splitId, CancellationToken cancellationToken = default);

    Task<ActiveSplitModel?> GetActiveAsync(Guid userId, CancellationToken cancellationToken = default);
}
