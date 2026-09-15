using Microsoft.Extensions.Logging;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="INotificationService"/>
public sealed class NotificationService(
    INotificationProvider notificationProvider,
    ILogger<NotificationService> logger) : INotificationService
{
    private const int MaxTokenLength = 512;

    public Task<ServiceResult<bool>> RegisterDeviceTokenAsync(
        Guid userId, RegisterDeviceTokenRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var token = NullIfBlank(request.Token);
            if (token is { Length: > MaxTokenLength })
            {
                throw new ValidationException("Push token is too long.", "That push token is not valid.");
            }

            var normalized = new RegisterDeviceTokenRequest
            {
                Token = token,
                Platform = NormalizePlatform(request.Platform),
                TimeZoneId = NormalizeTimeZone(request.TimeZoneId),
                NotificationsEnabled = request.NotificationsEnabled
            };

            await notificationProvider.RegisterDeviceTokenAsync(userId, normalized, DateTime.UtcNow, cancellationToken)
                .ConfigureAwait(false);
            logger.LogInformation("Registered notification device for user {UserId} (platform={Platform}, token={HasToken}).",
                userId, normalized.Platform, token is not null);
            return true;
        });

    public Task<ServiceResult<bool>> DeactivateDeviceTokenAsync(
        Guid userId, DeactivateDeviceTokenRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var token = NullIfBlank(request.Token)
                ?? throw new ValidationException("A push token is required.", "That push token is not valid.");

            await notificationProvider.DeactivateDeviceTokenAsync(userId, token, cancellationToken).ConfigureAwait(false);
            return true;
        });

    public Task<ServiceResult<bool>> RecordInteractionAsync(
        Guid userId, RecordNotificationInteractionRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            // A fresh timezone rides along with the interaction, so a device
            // that changed zones keeps getting reminders on its own clock.
            var normalizedTimeZone = NormalizeTimeZone(request.TimeZoneId);
            if (normalizedTimeZone is not null)
            {
                await notificationProvider.RegisterDeviceTokenAsync(
                    userId,
                    new RegisterDeviceTokenRequest { TimeZoneId = normalizedTimeZone },
                    DateTime.UtcNow,
                    cancellationToken).ConfigureAwait(false);
            }

            await notificationProvider
                .RecordInteractionAsync(userId, DateTime.UtcNow, request.NotificationId, cancellationToken)
                .ConfigureAwait(false);
            return true;
        });

    public Task<ServiceResult<bool>> RecordWorkoutHeartbeatAsync(
        Guid userId, Guid? workoutSessionId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await notificationProvider
                .RecordWorkoutHeartbeatAsync(userId, workoutSessionId, DateTime.UtcNow, cancellationToken)
                .ConfigureAwait(false);
            return true;
        });

    private static string NormalizePlatform(string? value) =>
        NullIfBlank(value)?.ToLowerInvariant() ?? "unknown";

    private static string? NormalizeTimeZone(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        if (!UserTimeZoneResolver.TryNormalize(value, out var normalized, out _))
        {
            throw new ValidationException($"Unsupported timezone '{value}'.", "We couldn't recognize your timezone.");
        }

        return normalized;
    }

    private static string? NullIfBlank(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
