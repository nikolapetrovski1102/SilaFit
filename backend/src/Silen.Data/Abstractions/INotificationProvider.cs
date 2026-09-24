using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>
/// Persistence for the notification publish pipeline: device-token registry,
/// per-user engagement state, the opted-in candidate feed, and the notification
/// outbox (create / mark sent / failed / skipped).
/// </summary>
public interface INotificationProvider
{
    Task RegisterDeviceTokenAsync(
        Guid userId, RegisterDeviceTokenRequest request, DateTime nowUtc, CancellationToken cancellationToken = default);

    Task DeactivateDeviceTokenAsync(Guid userId, string token, CancellationToken cancellationToken = default);

    Task<List<UserDeviceTokenModel>> GetActiveDeviceTokensAsync(Guid userId, CancellationToken cancellationToken = default);

    Task RecordInteractionAsync(
        Guid userId, DateTime atUtc, Guid? notificationId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Opted-in candidates for one publish run. <paramref name="maxUsers"/> is passed
    /// to the procedure so a run never materializes the whole opted-in user base.
    /// </summary>
    Task<List<NotificationCandidateModel>> GetCandidatesAsync(int maxUsers, CancellationToken cancellationToken = default);

    /// <summary>Returns the created notification, or null when its dedupe key was already used.</summary>
    Task<UserNotificationModel?> TryCreateNotificationAsync(
        NewNotificationModel notification, CancellationToken cancellationToken = default);

    /// <summary>
    /// Retry feed for the outbox: notifications left in 'Created' older than
    /// <paramref name="olderThanUtc"/> (a crashed run or a hard transport
    /// failure), oldest first, capped at <paramref name="maxRows"/>.
    /// </summary>
    Task<List<UserNotificationModel>> GetPendingNotificationsAsync(
        DateTime olderThanUtc, int maxRows, CancellationToken cancellationToken = default);

    Task MarkSentAsync(
        Guid notificationId, string category, string? providerMessageId, DateTime sentAtUtc,
        CancellationToken cancellationToken = default);

    Task MarkFailedAsync(Guid notificationId, string errorMessage, CancellationToken cancellationToken = default);

    Task MarkSkippedAsync(Guid notificationId, string reason, CancellationToken cancellationToken = default);

    Task RecordWorkoutHeartbeatAsync(
        Guid userId, Guid? workoutSessionId, DateTime atUtc, bool hasCompletedSets, CancellationToken cancellationToken = default);
}
