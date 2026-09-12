using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IWorkoutSessionProvider
{
    Task<(TodaySessionModel? Session, List<TargetExerciseModel> Exercises)> GetTodayScheduledAsync(
        Guid userId, CancellationToken cancellationToken = default);

    Task<WorkoutSessionCompletionModel?> CompleteAsync(
        Guid userId,
        Guid workoutSessionId,
        short durationMinutes,
        short? caloriesEstimate,
        decimal? rpeScore,
        decimal? tonnageKg,
        CancellationToken cancellationToken = default);

    Task<(RangeSummaryModel Summary, List<DaySessionStatusModel> Days)> GetRangeSummaryAsync(
        Guid userId, DateTime fromDateUtc, DateTime toDateUtc, CancellationToken cancellationToken = default);
}
