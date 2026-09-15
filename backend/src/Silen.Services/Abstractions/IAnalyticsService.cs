using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

public interface IAnalyticsService
{
    /// <summary>Defaults `year`/`month` to the current UTC month when omitted. Pro/Advanced only -
    /// throws ProUpgradeRequiredException otherwise. Returns a cached report for the month unless
    /// `refresh` is true (or none exists yet), in which case a fresh AI report is generated and cached.</summary>
    Task<ServiceResult<MonthlyAnalyticsDto>> GetMonthlyAsync(
        Guid userId, int? year, int? month, bool refresh, CancellationToken cancellationToken = default);

    /// <summary>Defaults `year`/`week` to the current UTC ISO week when omitted. ADVANCED only -
    /// throws AdvancedUpgradeRequiredException otherwise. The weekly counterpart of
    /// <see cref="GetMonthlyAsync"/>, cached per ISO year+week.</summary>
    Task<ServiceResult<WeeklyAnalyticsDto>> GetWeeklyAsync(
        Guid userId, int? year, int? week, bool refresh, CancellationToken cancellationToken = default);
}
