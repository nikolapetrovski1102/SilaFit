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
        IReadOnlyList<SetLogEntryModel>? setLogs,
        CancellationToken cancellationToken = default);

    Task<(RangeSummaryModel Summary, List<DaySessionStatusModel> Days)> GetRangeSummaryAsync(
        Guid userId, DateTime fromDateUtc, DateTime toDateUtc, CancellationToken cancellationToken = default);

    /// <summary>The heaviest set ever logged per exercise, most recently achieved first - see `usp_WorkoutSession_GetPersonalRecords`.</summary>
    Task<List<PersonalRecordModel>> GetPersonalRecordsAsync(
        Guid userId, int top, CancellationToken cancellationToken = default);
}
