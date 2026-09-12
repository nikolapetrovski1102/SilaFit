using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IAnalyticsProvider
{
    Task<MonthlySnapshotModel> GetMonthlySnapshotAsync(
        Guid userId, DateTime fromDateUtc, DateTime toDateUtc, CancellationToken cancellationToken = default);

    Task<AiPromptTemplateModel?> GetPromptTemplateAsync(string templateKey, CancellationToken cancellationToken = default);

    Task<MonthlyAnalyticsReportModel?> GetCachedReportAsync(
        Guid userId, int reportYear, int reportMonth, CancellationToken cancellationToken = default);

    Task<MonthlyAnalyticsReportModel> SaveReportAsync(
        Guid userId, int reportYear, int reportMonth, string snapshotJson, string resultJson,
        CancellationToken cancellationToken = default);
}
