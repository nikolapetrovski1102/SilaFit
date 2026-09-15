using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IAnalyticsProvider
{
    /// <summary>Builds the real-numbers snapshot for an arbitrary inclusive date range. Despite the
    /// underlying proc's "monthly" name (see usp_Analytics_GetMonthlySnapshot) the range is
    /// caller-supplied, so the same query backs both the monthly and weekly reports.</summary>
    Task<MonthlySnapshotModel> GetPeriodSnapshotAsync(
        Guid userId, DateTime fromDateUtc, DateTime toDateUtc, CancellationToken cancellationToken = default);

    Task<AiPromptTemplateModel?> GetPromptTemplateAsync(string templateKey, CancellationToken cancellationToken = default);

    Task<MonthlyAnalyticsReportModel?> GetCachedReportAsync(
        Guid userId, int reportYear, int reportMonth, CancellationToken cancellationToken = default);

    Task<MonthlyAnalyticsReportModel> SaveReportAsync(
        Guid userId, int reportYear, int reportMonth, string snapshotJson, string resultJson,
        CancellationToken cancellationToken = default);

    Task<WeeklyAnalyticsReportModel?> GetCachedWeeklyReportAsync(
        Guid userId, int reportYear, int reportWeek, CancellationToken cancellationToken = default);

    Task<WeeklyAnalyticsReportModel> SaveWeeklyReportAsync(
        Guid userId, int reportYear, int reportWeek, string snapshotJson, string resultJson,
        CancellationToken cancellationToken = default);
}
