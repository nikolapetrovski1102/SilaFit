using Microsoft.Extensions.Options;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="ISettingsService"/>
public sealed class SettingsService(
    IUserSettingsProvider userSettingsProvider,
    IOptions<NotificationPublishOptions> notificationOptions) : ISettingsService
{
    private static readonly string[] WeightUnits = ["kg", "lb"];
    private static readonly string[] DistanceUnits = ["km", "mi"];
    private static readonly string[] AppearanceModes = ["Dark", "Light", "Device"];
    // The two plain silhouettes plus 9 illustrated character avatars per
    // gender (see frontend/assets/avatars/male|female/) - the client's
    // gender-gated picker only ever offers a profile's own gender's set, but
    // this allow-list itself doesn't enforce that pairing, matching the
    // existing gender-agnostic validation used elsewhere in this service.
    private static readonly string[] AvatarChoices =
    [
        "Male", "Female",
        "Male1", "Male2", "Male3", "Male4", "Male5", "Male6", "Male7", "Male8", "Male9",
        "Female1", "Female2", "Female3", "Female4", "Female5", "Female6", "Female7", "Female8", "Female9",
    ];

    public Task<ServiceResult<UserSettingsModel>> GetAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
            WithDetectedReminderTime(await userSettingsProvider.GetAsync(userId, cancellationToken)
                ?? throw new NotFoundException($"Settings for user '{userId}' were not found.", "We couldn't find your settings.")));

    public Task<ServiceResult<UserSettingsModel>> UpdateAsync(Guid userId, UpdateUserSettingsRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            Validate(request);

            return WithDetectedReminderTime(await userSettingsProvider.UpdateAsync(userId, request, cancellationToken)
                ?? throw new NotFoundException($"Settings for user '{userId}' were not found.", "We couldn't find your settings."));
        });

    public Task<ServiceResult<UserSettingsModel>> SetAiDataConsentAsync(Guid userId, bool granted, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
            WithDetectedReminderTime(await userSettingsProvider.SetAiDataConsentAsync(userId, granted, cancellationToken)
                ?? throw new NotFoundException($"Settings for user '{userId}' were not found.", "We couldn't find your settings.")));

    /// <summary>
    /// Fills in the auto-mode reminder time the publisher will use, so Settings
    /// can show "Auto · 17:30" instead of a stale default.
    /// </summary>
    private UserSettingsModel WithDetectedReminderTime(UserSettingsModel settings)
    {
        if (!settings.NotificationTimeIsUserSet)
        {
            var timeZone = UserTimeZoneResolver.Resolve(settings.TimeZoneId);
            var nowUtc = DateTime.UtcNow;
            if (ReminderTimeDetector.DetectWorkoutTime(settings.RecentWorkoutStartsUtc, timeZone, nowUtc) is not null)
            {
                settings.DetectedNotificationLocalTime = ReminderTimeDetector.GymReminderTime(
                    settings.NotificationLocalTime, false, settings.RecentWorkoutStartsUtc, timeZone, nowUtc,
                    notificationOptions.Value.DetectedReminderOffsetMinutes);
            }
        }

        return settings;
    }

    private static void Validate(UpdateUserSettingsRequest request)
    {
        if (!WeightUnits.Contains(request.WeightUnit))
        {
            throw new ValidationException($"Unsupported weight unit '{request.WeightUnit}'.", "Choose kg or lb.");
        }

        if (!DistanceUnits.Contains(request.DistanceUnit))
        {
            throw new ValidationException($"Unsupported distance unit '{request.DistanceUnit}'.", "Choose km or mi.");
        }

        if (!AppearanceModes.Contains(request.AppearanceMode))
        {
            throw new ValidationException($"Unsupported appearance mode '{request.AppearanceMode}'.", "Choose dark, light, or device.");
        }

        if (!AvatarChoices.Contains(request.AvatarChoice))
        {
            throw new ValidationException($"Unsupported avatar choice '{request.AvatarChoice}'.", "Choose Male or Female.");
        }

        if (request.NotificationLocalTime < TimeSpan.Zero || request.NotificationLocalTime >= TimeSpan.FromDays(1))
        {
            throw new ValidationException(
                $"Invalid notification local time '{request.NotificationLocalTime}'.",
                "Choose a reminder time between 00:00 and 23:59.");
        }

        if (!UserTimeZoneResolver.TryNormalize(request.TimeZoneId, out var normalizedTimeZoneId, out _))
        {
            throw new ValidationException(
                $"Unsupported timezone '{request.TimeZoneId}'.",
                "Choose a valid timezone for your workout reminder.");
        }

        request.TimeZoneId = normalizedTimeZoneId;

        if (request.TargetWaterMl <= 0)
        {
            throw new ValidationException($"Invalid target water '{request.TargetWaterMl}'.", "Enter a valid daily water target.");
        }
    }
}
