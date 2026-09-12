using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class AnalyticsProvider(ISqlExecutor sqlExecutor) : IAnalyticsProvider
{
    public Task<MonthlySnapshotModel> GetMonthlySnapshotAsync(
        Guid userId, DateTime fromDateUtc, DateTime toDateUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Analytics_GetMonthlySnapshot",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@FromDateUtc", fromDateUtc.Date),
                SqlParameterBuilder.Create("@ToDateUtc", toDateUtc.Date)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AnalyticsRowMapper.MapMonthlySnapshot, cancellationToken),
            cancellationToken);

    public Task<AiPromptTemplateModel?> GetPromptTemplateAsync(string templateKey, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_AiPromptTemplate_GetActive",
            [SqlParameterBuilder.Create("@TemplateKey", templateKey)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, AnalyticsRowMapper.MapPromptTemplate, cancellationToken),
            cancellationToken);

    public Task<MonthlyAnalyticsReportModel?> GetCachedReportAsync(
        Guid userId, int reportYear, int reportMonth, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
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
        sqlExecutor.QueryAsync(
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
