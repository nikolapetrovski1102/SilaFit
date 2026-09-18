using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IUserProfileService"/>
public sealed class UserProfileService(
    IUserProfileProvider userProfileProvider,
    ISplitService splitService,
    IMealPlanningService mealPlanningService) : IUserProfileService
{
    private static readonly string[] Genders = ["Male", "Female", "Other"];
    private static readonly string[] Goals = ["BuildMuscle", "LoseFat", "MaintainActive"];

    public Task<ServiceResult<UserProfileModel>> GetAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
            await userProfileProvider.GetAsync(userId, cancellationToken)
                ?? throw new NotFoundException($"Profile for user '{userId}' was not found.", "We couldn't find your profile."));

    public Task<ServiceResult<UserProfileModel>> UpsertAsync(Guid userId, UpsertUserProfileRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            Validate(request);

            var profile = await userProfileProvider.UpsertAsync(userId, request, cancellationToken);

            // This is the one call site that writes the onboarding goal for the
            // first time (see `onboarding_controller.dart`'s single `submit()`),
            // so it's also where a first-time user gets a split picked for them
            // automatically - best-effort, since a hiccup here (or the split
            // library having nothing tagged for this goal yet) is no reason to
            // fail the profile save itself. `AutoAssignRecommendedAsync` is
            // itself a no-op for anyone who already has an active split, so
            // this is safe to run on every profile edit, not just the first.
            await splitService.AutoAssignRecommendedAsync(userId, profile, request.ForceSplitReassign, cancellationToken);

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
        if (request.TrainingDaysPerWeek is < 1 or > 7)
            throw new ValidationException("Invalid training days.", "Choose between 1 and 7 training days.");
        if (request.SessionDurationMinutes is < 15 or > 180)
            throw new ValidationException("Invalid session duration.", "Choose a workout duration between 15 and 180 minutes.");
        if (request.TrainingExperience is not null && !new[] { "Beginner", "Intermediate", "Advanced" }.Contains(request.TrainingExperience))
            throw new ValidationException("Invalid training experience.", "Choose a valid training experience option.");
        if (request.EquipmentAccess is not null && !new[] { "FullGym", "Dumbbells", "Bodyweight" }.Contains(request.EquipmentAccess))
            throw new ValidationException("Invalid equipment access.", "Choose a valid equipment access option.");
        if (request.DailyActivityLevel is not null && !new[] { "Sedentary", "LightlyActive", "Active", "VeryActive" }.Contains(request.DailyActivityLevel))
            throw new ValidationException("Invalid daily activity.", "Choose a valid daily activity option.");

        if (!Genders.Contains(request.Gender))
        {
            throw new ValidationException($"Unsupported gender '{request.Gender}'.", "Choose a valid gender option.");
        }

        if (!Goals.Contains(request.Goal))
        {
            throw new ValidationException($"Unsupported goal '{request.Goal}'.", "Choose a valid goal.");
        }

        if (request.AgeYears is < 13 or > 100)
        {
            throw new ValidationException($"Invalid age '{request.AgeYears}'.", "Enter an age between 13 and 100.");
        }

        if (request.HeightCm is < 100 or > 250)
        {
            throw new ValidationException($"Invalid height '{request.HeightCm}'.", "Enter a valid height.");
        }

        if (request.WeightKg is < 30 or > 300)
        {
            throw new ValidationException($"Invalid weight '{request.WeightKg}'.", "Enter a valid weight.");
        }
    }
}
