using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class WorkoutSessionProvider(ISqlExecutor sqlExecutor) : IWorkoutSessionProvider
{
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
        CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_WorkoutSession_Complete",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@WorkoutSessionId", workoutSessionId),
                SqlParameterBuilder.Create("@DurationMinutes", durationMinutes),
                SqlParameterBuilder.Create("@CaloriesEstimate", caloriesEstimate),
                SqlParameterBuilder.Create("@RpeScore", rpeScore),
                SqlParameterBuilder.Create("@TonnageKg", tonnageKg)
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
}
