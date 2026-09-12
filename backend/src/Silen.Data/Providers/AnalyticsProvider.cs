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

    public async Task<MonthlySnapshotModel> GetMonthlySnapshotAsync(
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
            snapshot.AvgCaloriesLogged = (decimal)loggedCalories.Average(entry => entry.CaloriesKcal);
        }

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
}
