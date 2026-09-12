using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IMealPlanningService"/>
public sealed class MealPlanningService(
    IMealPlanningProvider mealPlanningProvider,
    IUserProfileProvider userProfileProvider) : IMealPlanningService
{
    private static readonly string[] MealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"];
    private static readonly string[] Statuses = ["Planned", "Logged"];

    // Used when the user hasn't completed onboarding yet (no profile row), so
    // there's nothing to derive Mifflin-St Jeor targets from.
    private const short FallbackTargetCalories = 2200;
    private const short FallbackTargetProteinG = 150;
    private const short FallbackTargetCarbsG = 220;
    private const short FallbackTargetFatsG = 70;

    // No activity-level question in onboarding today, so a single moderate
    // multiplier stands in for everyone - revisit if that question is added.
    private const double ActivityMultiplier = 1.55;

    public Task<ServiceResult<MealDayDto>> GetDayAsync(Guid userId, DateOnly logDateUtc, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var targets = await GetOrCreateTargetsAsync(userId, cancellationToken);
            var meals = await mealPlanningProvider.GetForDateAsync(userId, logDateUtc, cancellationToken);

            var loggedMeals = meals.Where(m => m.Status == "Logged").ToList();

            return new MealDayDto
            {
                Targets = targets,
                Meals = meals,
                ConsumedCalories = loggedMeals.Sum(m => m.CaloriesKcal),
                RemainingCalories = targets.TargetCalories - loggedMeals.Sum(m => m.CaloriesKcal),
                ConsumedProteinG = loggedMeals.Sum(m => m.ProteinG),
                ConsumedCarbsG = loggedMeals.Sum(m => m.CarbsG),
                ConsumedFatsG = loggedMeals.Sum(m => m.FatsG)
            };
        });

    public Task<ServiceResult<MealLogModel>> UpsertMealAsync(Guid userId, UpsertMealLogRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (!MealTypes.Contains(request.MealType))
            {
                throw new ValidationException($"Unsupported meal type '{request.MealType}'.", "Choose a valid meal type.");
            }

            if (!Statuses.Contains(request.Status))
            {
                throw new ValidationException($"Unsupported meal status '{request.Status}'.", "That meal status isn't valid.");
            }

            if (string.IsNullOrWhiteSpace(request.Title))
            {
                throw new ValidationException("Meal title was blank.", "Give the meal a name.");
            }

            return await mealPlanningProvider.UpsertMealAsync(userId, request, cancellationToken);
        });

    public Task<ServiceResult<bool>> DeleteMealAsync(Guid userId, Guid mealLogId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(() => mealPlanningProvider.DeleteMealAsync(userId, mealLogId, cancellationToken));

    public Task<ServiceResult<UserNutritionTargetsModel>> GetTargetsAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(() => GetOrCreateTargetsAsync(userId, cancellationToken));

    public Task<ServiceResult<UserNutritionTargetsModel>> UpdateTargetsAsync(Guid userId, UpsertNutritionTargetsRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (request.TargetCalories <= 0)
            {
                throw new ValidationException($"Invalid target calories '{request.TargetCalories}'.", "Enter a valid daily calorie target.");
            }

            return await mealPlanningProvider.UpsertTargetsAsync(userId, request, cancellationToken);
        });

    public Task<ServiceResult<List<MealSuggestionModel>>> GetSuggestionsAsync(int? month, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var resolvedMonth = month ?? DateTime.UtcNow.Month;
            if (resolvedMonth is < 1 or > 12)
            {
                throw new ValidationException($"Invalid month '{resolvedMonth}'.", "That's not a valid month.");
            }

            return await mealPlanningProvider.GetSuggestionsForMonthAsync(resolvedMonth, cancellationToken);
        });

    /// <summary>
    /// First call ever for a user seeds targets from a Mifflin-St Jeor
    /// estimate (or flat fallbacks with no profile yet) and persists them,
    /// so every later read is a plain fetch.
    /// </summary>
    private async Task<UserNutritionTargetsModel> GetOrCreateTargetsAsync(Guid userId, CancellationToken cancellationToken)
    {
        var existing = await mealPlanningProvider.GetTargetsAsync(userId, cancellationToken);
        if (existing is not null)
        {
            return existing;
        }

        var profile = await userProfileProvider.GetAsync(userId, cancellationToken);
        var request = ComputeInitialTargets(profile);
        return await mealPlanningProvider.UpsertTargetsAsync(userId, request, cancellationToken);
    }

    private static UpsertNutritionTargetsRequest ComputeInitialTargets(UserProfileModel? profile)
    {
        if (profile is not { AgeYears: not null, HeightCm: not null, WeightKg: not null, Gender: not null, Goal: not null })
        {
            return new UpsertNutritionTargetsRequest
            {
                TargetCalories = FallbackTargetCalories,
                TargetProteinG = FallbackTargetProteinG,
                TargetCarbsG = FallbackTargetCarbsG,
                TargetFatsG = FallbackTargetFatsG
            };
        }

        var weightKg = (double)profile.WeightKg.Value;
        var heightCm = (double)profile.HeightCm.Value;
        var age = profile.AgeYears.Value;

        var bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * age) + profile.Gender switch
        {
            "Male" => 5,
            "Female" => -161,
            _ => -78
        };

        var tdee = bmr * ActivityMultiplier;

        var calorieTarget = profile.Goal switch
        {
            "BuildMuscle" => tdee + 250,
            "LoseFat" => tdee - 500,
            _ => tdee
        };

        var proteinG = weightKg * 2;
        var fatsG = calorieTarget * 0.25 / 9;
        var carbsG = (calorieTarget - (proteinG * 4) - (fatsG * 9)) / 4;

        return new UpsertNutritionTargetsRequest
        {
            TargetCalories = (short)Math.Clamp(Math.Round(calorieTarget), 1200, 6000),
            TargetProteinG = (short)Math.Clamp(Math.Round(proteinG), 0, 400),
            TargetCarbsG = (short)Math.Clamp(Math.Round(Math.Max(carbsG, 0)), 0, 800),
            TargetFatsG = (short)Math.Clamp(Math.Round(fatsG), 0, 300)
        };
    }
}
