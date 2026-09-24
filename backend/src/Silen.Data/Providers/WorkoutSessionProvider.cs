using System.Text.Json;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class WorkoutSessionProvider(ISqlExecutor sqlExecutor) : IWorkoutSessionProvider
{
    // camelCase to match the `$.exerciseId`/`$.setNumber`/... paths
    // `usp_WorkoutSession_Complete`'s OPENJSON call expects.
    private static readonly JsonSerializerOptions SetLogsJsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public Task<(TodaySessionModel? Session, List<TargetExerciseModel> Exercises)> GetTodayScheduledAsync(
        Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_WorkoutSession_GetTodayScheduled",
            [SqlParameterBuilder.Create("@UserId", userId)],
            async reader =>
            {
                var session = await SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapTodaySession, cancellationToken);
                await reader.NextResultAsync(cancellationToken);
                var exercises = await SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapTargetExercise, cancellationToken);
                return (session, exercises);
            },
            cancellationToken);

    public Task<WorkoutSessionCompletionModel?> CompleteAsync(
        Guid userId,
        Guid workoutSessionId,
        short durationMinutes,
        short? caloriesEstimate,
        decimal? rpeScore,
        decimal? tonnageKg,
        IReadOnlyList<SetLogEntryModel>? setLogs,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_WorkoutSession_Complete",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@WorkoutSessionId", workoutSessionId),
                SqlParameterBuilder.Create("@DurationMinutes", durationMinutes),
                SqlParameterBuilder.Create("@CaloriesEstimate", caloriesEstimate),
                SqlParameterBuilder.Create("@RpeScore", rpeScore),
                SqlParameterBuilder.Create("@TonnageKg", tonnageKg),
                SqlParameterBuilder.Create("@SetLogsJson",
                    setLogs is { Count: > 0 } ? JsonSerializer.Serialize(setLogs, SetLogsJsonOptions) : null)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapCompletion, cancellationToken),
            cancellationToken);

    public Task<(RangeSummaryModel Summary, List<DaySessionStatusModel> Days)> GetRangeSummaryAsync(
        Guid userId, DateTime fromDateUtc, DateTime toDateUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_WorkoutSession_GetRangeSummary",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@FromDateUtc", fromDateUtc.Date),
                SqlParameterBuilder.Create("@ToDateUtc", toDateUtc.Date)
            ],
            async reader =>
            {
                var summary = await SqlResultSetReader.ReadScalarRowAsync(reader, WorkoutRowMapper.MapRangeSummary, cancellationToken);
                await reader.NextResultAsync(cancellationToken);
                var days = await SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapDaySessionStatus, cancellationToken);
                return (summary, days);
            },
            cancellationToken);

    public Task<List<PersonalRecordModel>> GetPersonalRecordsAsync(
        Guid userId, int top, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_WorkoutSession_GetPersonalRecords",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@Top", top)
            ],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapPersonalRecord, cancellationToken),
            cancellationToken);

    public Task<List<SetLogModel>> GetSetLogsByDateAsync(
        Guid userId, DateTime scheduledDateUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_WorkoutSession_GetSetLogsByDate",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@ScheduledDateUtc", scheduledDateUtc.Date)
            ],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapSetLog, cancellationToken),
            cancellationToken);

    public Task<List<SetLogModel>> GetExerciseHistoryAsync(
        Guid userId, Guid exerciseId, int top, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_WorkoutSetLog_GetHistoryByExercise",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@ExerciseId", exerciseId),
                SqlParameterBuilder.Create("@Top", top)
            ],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapSetLog, cancellationToken),
            cancellationToken);

    public Task<List<TrackedExerciseModel>> GetTrackedExercisesAsync(
        Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_WorkoutSetLog_GetTrackedExercises",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapTrackedExercise, cancellationToken),
            cancellationToken);

    public Task<List<ExerciseProgressPointModel>> GetExerciseProgressAsync(
        Guid userId, Guid exerciseId, DateTime fromDateUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_WorkoutSetLog_GetExerciseProgress",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@ExerciseId", exerciseId),
                SqlParameterBuilder.Create("@FromDateUtc", fromDateUtc.Date)
            ],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapExerciseProgressPoint, cancellationToken),
            cancellationToken);
}
