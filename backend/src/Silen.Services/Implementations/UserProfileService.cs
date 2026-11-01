using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IUserProfileService"/>
public sealed class UserProfileService(
    IUserProfileProvider userProfileProvider,
    IMealPlanningService mealPlanningService) : IUserProfileService
{
    public Task<ServiceResult<UserProfileModel>> GetAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
            await userProfileProvider.GetAsync(userId, cancellationToken)
                ?? throw new NotFoundException($"Profile for user '{userId}' was not found.", "We couldn't find your profile."));

    public Task<ServiceResult<UserProfileModel>> UpsertAsync(Guid userId, UpsertUserProfileRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            Validate(request);

            var profile = await userProfileProvider.UpsertAsync(userId, request, cancellationToken);

            // Targets are derived from the profile (weight/height/age/gender/goal/
            // activity), so a profile save is the moment they should be refreshed
            // rather than frozen at onboarding. Best-effort like the split above:
            // it's a no-op when the user has set targets manually, and a hiccup
            // here shouldn't fail the profile save itself.
            await mealPlanningService.RecomputeTargetsAsync(userId, profile, cancellationToken);

            return profile;
        });

    private static void Validate(UpsertUserProfileRequest request)
    {
        if (request.TrainingDaysPerWeek is < UserProfileRules.MinTrainingDaysPerWeek or > UserProfileRules.MaxTrainingDaysPerWeek)
            throw new ValidationException("Invalid training days.", "Choose between 1 and 7 training days.");
        if (request.SessionDurationMinutes is < UserProfileRules.MinSessionDurationMinutes or > UserProfileRules.MaxSessionDurationMinutes)
            throw new ValidationException("Invalid session duration.", "Choose a workout duration between 15 and 180 minutes.");
        if (request.TrainingExperience is not null && !UserProfileRules.TrainingExperiences.Contains(request.TrainingExperience))
            throw new ValidationException("Invalid training experience.", "Choose a valid training experience option.");
        if (request.EquipmentAccess is not null && !UserProfileRules.EquipmentAccesses.Contains(request.EquipmentAccess))
            throw new ValidationException("Invalid equipment access.", "Choose a valid equipment access option.");
        if (request.DailyActivityLevel is not null && !UserProfileRules.DailyActivityLevels.Contains(request.DailyActivityLevel))
            throw new ValidationException("Invalid daily activity.", "Choose a valid daily activity option.");

        if (!UserProfileRules.Genders.Contains(request.Gender))
        {
            throw new ValidationException($"Unsupported gender '{request.Gender}'.", "Choose a valid gender option.");
        }

        if (!UserProfileRules.Goals.Contains(request.Goal))
        {
            throw new ValidationException($"Unsupported goal '{request.Goal}'.", "Choose a valid goal.");
        }

        if (request.AgeYears is < UserProfileRules.MinAgeYears or > UserProfileRules.MaxAgeYears)
        {
            throw new ValidationException($"Invalid age '{request.AgeYears}'.", "Enter an age between 13 and 100.");
        }

        if (request.HeightCm is < UserProfileRules.MinHeightCm or > UserProfileRules.MaxHeightCm)
        {
            throw new ValidationException($"Invalid height '{request.HeightCm}'.", "Enter a valid height.");
        }

        if (request.WeightKg is < UserProfileRules.MinWeightKg or > UserProfileRules.MaxWeightKg)
        {
            throw new ValidationException($"Invalid weight '{request.WeightKg}'.", "Enter a valid weight.");
        }
    }
}
