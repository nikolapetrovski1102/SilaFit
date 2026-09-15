using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

/// <summary>
/// The notification publish batch. Decides, per opted-in user and in their own
/// timezone, which reminder (if any) is due now, composes it, and pushes it.
/// Safe to run as often as every few minutes - dedupe keys make re-runs no-ops.
/// </summary>
public interface INotificationPublishService
{
    Task<ServiceResult<NotificationPublishSummaryDto>> RunAsync(
        bool dryRun = false,
        Guid? onlyUserId = null,
        int? limit = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Re-delivers notifications a previous run left in 'Created' (crashed
    /// process or hard transport failure) instead of letting them be stranded.
    /// Runs after the normal publish pass on the same schedule; delivery moves a
    /// row to a terminal status, so it is safe to run as often as the batch.
    /// </summary>
    Task<ServiceResult<NotificationPublishSummaryDto>> FlushPendingAsync(
        bool dryRun = false,
        Guid? onlyUserId = null,
        CancellationToken cancellationToken = default);
}
