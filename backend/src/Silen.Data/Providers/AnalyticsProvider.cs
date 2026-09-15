using Microsoft.Extensions.Options;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class AnalyticsProvider : IAnalyticsProvider
{
    private readonly ISqlExecutor _sqlExecutor;
    private readonly IBodyweightProvider _bodyweightProvider;
    private readonly IMealPlanningProvider _mealPlanningProvider;
    private readonly byte[] _key;

    public AnalyticsProvider(
        ISqlExecutor sqlExecutor,
        IBodyweightProvider bodyweightProvider,
        IMealPlanningProvider mealPlanningProvider,
        IOptions<EncryptionOptions> encryptionOptions)
    {
        _sqlExecutor = sqlExecutor;
        _bodyweightProvider = bodyweightProvider;
        _mealPlanningProvider = mealPlanningProvider;
        _key = Convert.FromBase64String(encryptionOptions.Value.MasterKeyBase64);
    }

    public async Task<MonthlySnapshotModel> GetPeriodSnapshotAsync(
        Guid userId, DateTime fromDateUtc, DateTime toDateUtc, CancellationToken cancellationToken = default)
    {
        var snapshot = await _sqlExecutor.QueryAsync(
            "dbo.usp_Analytics_GetMonthlySnapshot",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@FromDateUtc", fromDateUtc.Date),
                SqlParameterBuilder.Create("@ToDateUtc", toDateUtc.Date)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, r => AnalyticsRowMapper.MapMonthlySnapshot(r, _key), cancellationToken),
            cancellationToken);

        var fromDate = DateOnly.FromDateTime(fromDateUtc);
        var toDate = DateOnly.FromDateTime(toDateUtc);

        // BodyweightLogs.WeightKg and MealLogs.CaloriesKcal are AES-256-GCM ciphertext, so these
        // two figures can no longer be computed inside usp_Analytics_GetMonthlySnapshot - decrypt
        // and aggregate here instead, reusing the same providers the regular endpoints use.
        var bodyweightEntries = await _bodyweightProvider.GetInRangeAsync(userId, fromDate, toDate, cancellationToken);
        if (bodyweightEntries.Count > 0)
        {
            snapshot.StartWeightKg = bodyweightEntries[0].WeightKg;
            snapshot.EndWeightKg = bodyweightEntries[^1].WeightKg;
        }

        var loggedCalories = await _mealPlanningProvider.GetCaloriesInRangeAsync(userId, fromDate, toDate, cancellationToken);
        if (loggedCalories.Count > 0)
        {
            var dailyCalories = loggedCalories.GroupBy(entry => entry.LogDateUtc)
                .Select(day => day.Sum(entry => entry.CaloriesKcal)).ToList();
            snapshot.AvgCaloriesLogged = (decimal)dailyCalories.Average();
            if (snapshot.TargetCalories is > 0)
            {
                snapshot.DaysOverCalorieTarget = dailyCalories.Count(total => total > snapshot.TargetCalories.Value);
                snapshot.TotalCaloriesOverTarget = dailyCalories.Sum(total => Math.Max(0, total - snapshot.TargetCalories.Value));
            }
        }

        await _sqlExecutor.QueryAsync(
            "dbo.usp_Analytics_GetMonthlyExerciseHistory",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@FromDateUtc", fromDateUtc.Date),
                SqlParameterBuilder.Create("@ToDateUtc", toDateUtc.Date)
            ],
            async reader =>
            {
                snapshot.MissedWorkoutDays = await SqlResultSetReader.ReadScalarRowAsync(
                    reader, r => r.GetInt32Value("MissedWorkoutDays"), cancellationToken);
                await reader.NextResultAsync(cancellationToken);
                var exercises = new Dictionary<Guid, MonthlyExerciseModel>();
                while (await reader.ReadAsync(cancellationToken))
                {
                    var id = reader.GetGuidValue("ExerciseId");
                    if (!exercises.TryGetValue(id, out var exercise))
                    {
                        exercise = new MonthlyExerciseModel
                        {
                            ExerciseId = id,
                            ExerciseName = reader.GetStringValue("ExerciseName"),
                            RecordWeightKg = reader.GetDecimalValue("RecordWeightKg")
                        };
                        exercises.Add(id, exercise);
                    }
                    exercise.Points.Add(new MonthlyExercisePointModel
                    {
                        DateUtc = DateTime.SpecifyKind(reader.GetDateTimeValue("CompletedAtUtc"), DateTimeKind.Utc),
                        WeightKg = reader.GetDecimalValue("WeightKg"),
                        Reps = reader.GetInt16Value("Reps"),
                        SessionRpe = reader.GetNullableDecimal("RpeScore")
                    });
                }
                snapshot.Exercises = exercises.Values.ToList();
                return true;
            }, cancellationToken);
        snapshot.RecapVersion = 2;
        return snapshot;
    }

    public Task<AiPromptTemplateModel?> GetPromptTemplateAsync(string templateKey, CancellationToken cancellationToken = default) =>
        _sqlExecutor.QueryAsync(
            "dbo.usp_AiPromptTemplate_GetActive",
            [SqlParameterBuilder.Create("@TemplateKey", templateKey)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, AnalyticsRowMapper.MapPromptTemplate, cancellationToken),
            cancellationToken);

    public Task<MonthlyAnalyticsReportModel?> GetCachedReportAsync(
        Guid userId, int reportYear, int reportMonth, CancellationToken cancellationToken = default) =>
        _sqlExecutor.QueryAsync(
            "dbo.usp_Analytics_GetCachedReport",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@ReportYear", (short)reportYear),
                SqlParameterBuilder.Create("@ReportMonth", (byte)reportMonth)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, AnalyticsRowMapper.MapReport, cancellationToken),
            cancellationToken);

    public Task<MonthlyAnalyticsReportModel> SaveReportAsync(
        Guid userId, int reportYear, int reportMonth, string snapshotJson, string resultJson,
        CancellationToken cancellationToken = default) =>
        _sqlExecutor.QueryAsync(
            "dbo.usp_Analytics_UpsertReport",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@ReportYear", (short)reportYear),
                SqlParameterBuilder.Create("@ReportMonth", (byte)reportMonth),
                SqlParameterBuilder.Create("@SnapshotJson", snapshotJson),
                SqlParameterBuilder.Create("@ResultJson", resultJson)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AnalyticsRowMapper.MapReport, cancellationToken),
            cancellationToken);

    public Task<WeeklyAnalyticsReportModel?> GetCachedWeeklyReportAsync(
        Guid userId, int reportYear, int reportWeek, CancellationToken cancellationToken = default) =>
        _sqlExecutor.QueryAsync(
            "dbo.usp_Analytics_GetCachedWeeklyReport",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@ReportYear", (short)reportYear),
                SqlParameterBuilder.Create("@ReportWeek", (byte)reportWeek)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, AnalyticsRowMapper.MapWeeklyReport, cancellationToken),
            cancellationToken);

    public Task<WeeklyAnalyticsReportModel> SaveWeeklyReportAsync(
        Guid userId, int reportYear, int reportWeek, string snapshotJson, string resultJson,
        CancellationToken cancellationToken = default) =>
        _sqlExecutor.QueryAsync(
            "dbo.usp_Analytics_UpsertWeeklyReport",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@ReportYear", (short)reportYear),
                SqlParameterBuilder.Create("@ReportWeek", (byte)reportWeek),
                SqlParameterBuilder.Create("@SnapshotJson", snapshotJson),
                SqlParameterBuilder.Create("@ResultJson", resultJson)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AnalyticsRowMapper.MapWeeklyReport, cancellationToken),
            cancellationToken);
}
