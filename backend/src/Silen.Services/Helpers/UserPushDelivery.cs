using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Helpers;

/// <summary>
/// Delivers one already-created outbox notification to every active device of its
/// user, then moves the outbox row to Sent / Failed / Skipped. Tokens the provider
/// says can never work again are deactivated on the way. Shared by the one-off
/// senders (weekly AI plan, trainer assignments) that push outside the publish batch.
/// </summary>
public static class UserPushDelivery
{
    private const int MaxErrorMessageLength = 1000;

    /// <returns>True when at least one device accepted the message.</returns>
    public static async Task<bool> DeliverAsync(
        INotificationProvider notificationProvider,
        IPushNotificationSender pushSender,
        UserNotificationModel notification,
        string defaultScreen,
        CancellationToken cancellationToken)
    {
        var userId = notification.UserId;
        var tokens = await notificationProvider.GetActiveDeviceTokensAsync(userId, cancellationToken).ConfigureAwait(false);
        if (tokens.Count == 0)
        {
            await notificationProvider
                .MarkSkippedAsync(notification.NotificationId, "No active device tokens.", cancellationToken)
                .ConfigureAwait(false);
            return false;
        }

        var delivered = false;
        string? providerMessageId = null;
        var errors = new List<string>();

        foreach (var token in tokens)
        {
            var message = new PushNotificationMessage
            {
                Token = token.PushToken,
                Title = notification.Title,
                Body = notification.Body,
                Data = new Dictionary<string, string>
                {
                    ["notificationId"] = notification.NotificationId.ToString(),
                    ["category"] = notification.Category,
                    ["screen"] = notification.DeepLink ?? defaultScreen
                }
            };

            PushSendResult result;
            try
            {
                result = await pushSender.SendAsync(message, cancellationToken).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                result = PushSendResult.Failed(ex.Message);
            }

            if (result.Success)
            {
                delivered = true;
                providerMessageId ??= result.ProviderMessageId;
                continue;
            }

            errors.Add($"{token.Platform}: {result.Error}");
            if (result.TokenInvalid)
            {
                await notificationProvider.DeactivateDeviceTokenAsync(userId, token.PushToken, cancellationToken)
                    .ConfigureAwait(false);
            }
        }

        if (delivered)
        {
            await notificationProvider
                .MarkSentAsync(notification.NotificationId, notification.Category, providerMessageId, DateTime.UtcNow, cancellationToken)
                .ConfigureAwait(false);
            return true;
        }

        var error = errors.Count > 0 ? string.Join("; ", errors) : "Push delivery failed.";
        if (error.Length > MaxErrorMessageLength)
        {
            error = error[..MaxErrorMessageLength];
        }
        await notificationProvider
            .MarkFailedAsync(notification.NotificationId, error, cancellationToken)
            .ConfigureAwait(false);
        return false;
    }
}
