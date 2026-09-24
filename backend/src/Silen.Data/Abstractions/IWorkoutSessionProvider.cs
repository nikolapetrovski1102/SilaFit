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

    /// <summary>Every set logged for the session scheduled on <paramref name="scheduledDateUtc"/> - see `usp_WorkoutSession_GetSetLogsByDate`.</summary>
    Task<List<SetLogModel>> GetSetLogsByDateAsync(
        Guid userId, DateTime scheduledDateUtc, CancellationToken cancellationToken = default);

    /// <summary>Every set logged for one exercise, across its most recent <paramref name="top"/> sessions - see `usp_WorkoutSetLog_GetHistoryByExercise`.</summary>
    Task<List<SetLogModel>> GetExerciseHistoryAsync(
        Guid userId, Guid exerciseId, int top, CancellationToken cancellationToken = default);

    /// <summary>Every exercise the user has logged a set for, most recently trained first - see `usp_WorkoutSetLog_GetTrackedExercises`.</summary>
    Task<List<TrackedExerciseModel>> GetTrackedExercisesAsync(
        Guid userId, CancellationToken cancellationToken = default);

    /// <summary>One row per session <paramref name="exerciseId"/> was trained in since <paramref name="fromDateUtc"/>, oldest first - see `usp_WorkoutSetLog_GetExerciseProgress`.</summary>
    Task<List<ExerciseProgressPointModel>> GetExerciseProgressAsync(
        Guid userId, Guid exerciseId, DateTime fromDateUtc, CancellationToken cancellationToken = default);
}
