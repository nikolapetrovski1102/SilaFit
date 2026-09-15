using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class NotificationProvider(ISqlExecutor sqlExecutor) : INotificationProvider
{
    public Task RegisterDeviceTokenAsync(
        Guid userId, RegisterDeviceTokenRequest request, DateTime nowUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_Notification_RegisterDeviceToken",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@Token", NormalizeToken(request.Token)),
                SqlParameterBuilder.Create("@Platform", NormalizePlatform(request.Platform)),
                SqlParameterBuilder.Create("@TimeZoneId", Normalize(request.TimeZoneId)),
                SqlParameterBuilder.Create("@NotificationsEnabled", request.NotificationsEnabled),
                SqlParameterBuilder.Create("@NowUtc", nowUtc)
            ],
            cancellationToken);

    public Task DeactivateDeviceTokenAsync(Guid userId, string token, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_Notification_DeactivateDeviceToken",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@Token", token)
            ],
            cancellationToken);

    public Task<List<UserDeviceTokenModel>> GetActiveDeviceTokensAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Notification_GetActiveDeviceTokens",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadListAsync(reader, NotificationRowMapper.MapDeviceToken, cancellationToken),
            cancellationToken);

    public Task RecordInteractionAsync(
        Guid userId, DateTime atUtc, Guid? notificationId, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_Notification_RecordInteraction",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@AtUtc", atUtc),
                SqlParameterBuilder.Create("@NotificationId", notificationId)
            ],
            cancellationToken);

    public Task<List<NotificationCandidateModel>> GetCandidatesAsync(int maxUsers, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_NotificationPublish_GetCandidates",
            [
                SqlParameterBuilder.Create("@MaxUsers", maxUsers)
            ],
            reader => SqlResultSetReader.ReadListAsync(reader, NotificationRowMapper.MapCandidate, cancellationToken),
            cancellationToken);

    public Task<UserNotificationModel?> TryCreateNotificationAsync(
        NewNotificationModel notification, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_NotificationPublish_TryCreate",
            [
                SqlParameterBuilder.Create("@UserId", notification.UserId),
                SqlParameterBuilder.Create("@Category", notification.Category),
                SqlParameterBuilder.Create("@Title", notification.Title),
                SqlParameterBuilder.Create("@Body", notification.Body),
                SqlParameterBuilder.Create("@DeepLink", notification.DeepLink),
                SqlParameterBuilder.Create("@DedupeKey", notification.DedupeKey),
                SqlParameterBuilder.Create("@ScheduledLocalAt", notification.ScheduledLocalAt)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, NotificationRowMapper.MapNotification, cancellationToken),
            cancellationToken);

    public Task<List<UserNotificationModel>> GetPendingNotificationsAsync(
        DateTime olderThanUtc, int maxRows, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_NotificationPublish_GetPending",
            [
                SqlParameterBuilder.Create("@OlderThanUtc", olderThanUtc),
                SqlParameterBuilder.Create("@MaxRows", maxRows)
            ],
            reader => SqlResultSetReader.ReadListAsync(reader, NotificationRowMapper.MapNotification, cancellationToken),
            cancellationToken);

    public Task MarkSentAsync(
        Guid notificationId, string category, string? providerMessageId, DateTime sentAtUtc,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_NotificationPublish_MarkSent",
            [
                SqlParameterBuilder.Create("@NotificationId", notificationId),
                SqlParameterBuilder.Create("@Category", category),
                SqlParameterBuilder.Create("@ProviderMessageId", providerMessageId),
                SqlParameterBuilder.Create("@SentAtUtc", sentAtUtc)
            ],
            cancellationToken);

    public Task MarkFailedAsync(Guid notificationId, string errorMessage, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_NotificationPublish_MarkFailed",
            [
                SqlParameterBuilder.Create("@NotificationId", notificationId),
                SqlParameterBuilder.Create("@ErrorMessage", errorMessage)
            ],
            cancellationToken);

    public Task MarkSkippedAsync(Guid notificationId, string reason, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_NotificationPublish_MarkSkipped",
            [
                SqlParameterBuilder.Create("@NotificationId", notificationId),
                SqlParameterBuilder.Create("@Reason", reason)
            ],
            cancellationToken);

    public Task RecordWorkoutHeartbeatAsync(
        Guid userId, Guid? workoutSessionId, DateTime atUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_WorkoutSession_Heartbeat",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@WorkoutSessionId", workoutSessionId),
                SqlParameterBuilder.Create("@AtUtc", atUtc)
            ],
            cancellationToken);

    private static string? Normalize(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static string? NormalizeToken(string? value)
    {
        var token = Normalize(value);
        return token is null ? null : token.Length <= 512 ? token : token[..512];
    }

    private static string NormalizePlatform(string? value)
    {
        var platform = Normalize(value)?.ToLowerInvariant() ?? "unknown";
        return platform.Length <= 20 ? platform : platform[..20];
    }
}
