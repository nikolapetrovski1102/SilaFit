using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="ISettingsService"/>
public sealed class SettingsService(IUserSettingsProvider userSettingsProvider) : ISettingsService
{
    private static readonly string[] WeightUnits = ["kg", "lb"];
    private static readonly string[] DistanceUnits = ["km", "mi"];
    private static readonly string[] AppearanceModes = ["Dark", "Light", "Device"];

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
