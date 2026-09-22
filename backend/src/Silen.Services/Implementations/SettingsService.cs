using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="ISettingsService"/>
public sealed class SettingsService(IUserSettingsProvider userSettingsProvider) : ISettingsService
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
            await userSettingsProvider.GetAsync(userId, cancellationToken)
                ?? throw new NotFoundException($"Settings for user '{userId}' were not found.", "We couldn't find your settings."));

    public Task<ServiceResult<UserSettingsModel>> UpdateAsync(Guid userId, UpdateUserSettingsRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            Validate(request);

            return await userSettingsProvider.UpdateAsync(userId, request, cancellationToken)
                ?? throw new NotFoundException($"Settings for user '{userId}' were not found.", "We couldn't find your settings.");
        });

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

        if (request.BarbellStandardKg <= 0)
        {
            throw new ValidationException($"Invalid barbell standard '{request.BarbellStandardKg}'.", "Enter a valid barbell weight.");
        }

        if (request.TargetWaterMl <= 0)
        {
            throw new ValidationException($"Invalid target water '{request.TargetWaterMl}'.", "Enter a valid daily water target.");
        }
    }
}
