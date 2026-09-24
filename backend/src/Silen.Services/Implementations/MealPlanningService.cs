using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IMealPlanningService"/>
public sealed class MealPlanningService(
    IMealPlanningProvider mealPlanningProvider,
    IUserProfileProvider userProfileProvider) : IMealPlanningService
{
    private static readonly string[] MealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"];
    private static readonly string[] Statuses = ["Planned", "Logged"];

    private const int MaxMealItems = 50;
    private const decimal MaxItemGrams = 5000;

    // Used when the user hasn't completed onboarding yet (no profile row), so
    // there's nothing to derive Mifflin-St Jeor targets from.
    private const short FallbackTargetCalories = 2200;
    private const short FallbackTargetProteinG = 150;
    private const short FallbackTargetCarbsG = 220;
    private const short FallbackTargetFatsG = 70;

    // Mifflin-St Jeor activity multipliers, keyed by the onboarding
    // DailyActivityLevel answer. The default (1.55, "moderately active") is used
    // for profiles that predate the activity question and have no answer.
    // These capture non-exercise/occupational movement only; the planned
    // training itself is added separately by WeeklyTrainingCaloriesPerDay.
    private const double DefaultActivityMultiplier = 1.55;

    // Rough energy cost of a resistance-training session, in METs. Kept at the
    // moderate "vigorous weight training" band so the training contribution is a
    // sensible addition rather than dominating the resting/occupational TDEE.
    private const double TrainingMet = 6.0;

    private static double ActivityMultiplierFor(string? dailyActivityLevel) => dailyActivityLevel switch
    {
        "Sedentary" => 1.2,
        "LightlyActive" => 1.375,
        "Active" => 1.55,
        "VeryActive" => 1.725,
        _ => DefaultActivityMultiplier
    };

    /// <summary>
    /// The average daily energy cost of the user's planned training, from the
    /// onboarding training-days-per-week and session-length answers, spread over
    /// the week. This is what makes two otherwise-identical profiles differ by
    /// how many active days they train. Missing answers (legacy profiles) add
    /// nothing, so those targets are unchanged.
    /// </summary>
    private static double WeeklyTrainingCaloriesPerDay(
        int? trainingDaysPerWeek, int? sessionDurationMinutes, double weightKg)
    {
        if (trainingDaysPerWeek is not { } days || sessionDurationMinutes is not { } minutes)
        {
            return 0;
        }

        // kcal/min = MET * 3.5 * kg / 200 (standard MET-to-kcal conversion).
        var kcalPerMinute = TrainingMet * 3.5 * weightKg / 200.0;
        return days * minutes * kcalPerMinute / 7.0;
    }

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

            if (request.Items is { Count: > 0 } items)
            {
                ApplyItemTotals(request, items);
            }

            return await mealPlanningProvider.UpsertMealAsync(userId, request, cancellationToken);
        });

    /// <summary>
    /// A meal built food-by-food: validates each item and makes the meal's
    /// stored totals the sum of its foods, so the client can't send totals
    /// that disagree with the list it shows. Item macros are already scaled
    /// to the logged grams (snapshotted from the catalog at log time).
    /// </summary>
    private static void ApplyItemTotals(UpsertMealLogRequest request, List<MealLogItemModel> items)
    {
        if (items.Count > MaxMealItems)
        {
            throw new ValidationException($"Meal had {items.Count} items.", $"A meal can hold up to {MaxMealItems} foods.");
        }

        foreach (var item in items)
        {
            if (string.IsNullOrWhiteSpace(item.Name))
            {
                throw new ValidationException("Meal item name was blank.", "Every food needs a name.");
            }

            if (item.Grams is <= 0 or > MaxItemGrams)
            {
                throw new ValidationException($"Invalid item grams '{item.Grams}'.", $"Enter an amount between 1 and {MaxItemGrams} g.");
            }

            if (item.CaloriesKcal < 0 || item.ProteinG < 0 || item.CarbsG < 0 || item.FatsG < 0
                || item.FiberG < 0 || item.SugarG < 0 || item.SodiumMg < 0)
            {
                throw new ValidationException("Meal item had a negative macro.", "Macros can't be negative.");
            }

            item.Name = item.Name.Trim();
            item.BrandName = string.IsNullOrWhiteSpace(item.BrandName) ? null : item.BrandName.Trim();
            item.Grams = Math.Round(item.Grams, 1);
            item.CaloriesKcal = Math.Round(item.CaloriesKcal, 1);
            item.ProteinG = Math.Round(item.ProteinG, 1);
            item.CarbsG = Math.Round(item.CarbsG, 1);
            item.FatsG = Math.Round(item.FatsG, 1);
            item.FiberG = item.FiberG is { } fiber ? Math.Round(fiber, 1) : null;
            item.SugarG = item.SugarG is { } sugar ? Math.Round(sugar, 1) : null;
            item.SodiumMg = item.SodiumMg is { } sodium ? Math.Round(sodium, 0) : null;
        }

        request.CaloriesKcal = ToTotal(items.Sum(i => i.CaloriesKcal));
        request.ProteinG = ToTotal(items.Sum(i => i.ProteinG));
        request.CarbsG = ToTotal(items.Sum(i => i.CarbsG));
        request.FatsG = ToTotal(items.Sum(i => i.FatsG));
    }

    private static short ToTotal(decimal value) =>
        (short)Math.Min(short.MaxValue, Math.Round(value, MidpointRounding.AwayFromZero));

    public Task<ServiceResult<int>> ApplyPlannedMealsAsync(Guid userId, List<UpsertMealLogRequest> requests, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var applied = 0;
            var existingByDate = new Dictionary<DateOnly, List<MealLogModel>>();

            foreach (var request in requests)
            {
                if (!existingByDate.TryGetValue(request.LogDateUtc, out var existing))
                {
                    existing = await mealPlanningProvider.GetForDateAsync(userId, request.LogDateUtc, cancellationToken);
                    existingByDate[request.LogDateUtc] = existing;
                }

                // A meal the caller already has for this day - planned, edited, or
                // logged - is left alone, matched by type+title the same way the
                // Active Diet Plan card matches a "Log" tap back to its plan meal.
                if (existing.Any(m => m.MealType == request.MealType && m.Title == request.Title))
                {
                    continue;
                }

                var created = await mealPlanningProvider.UpsertMealAsync(userId, request, cancellationToken);
                existing.Add(created);
                applied++;
            }

            return applied;
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

            // Explicit user edit: pin it so a later profile save doesn't recompute
            // over the top of a choice they made deliberately.
            request.IsManualOverride = true;
            return await mealPlanningProvider.UpsertTargetsAsync(userId, request, cancellationToken);
        });

    public Task<ServiceResult<UserNutritionTargetsModel>> RecomputeTargetsAsync(Guid userId, UserProfileModel profile, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var existing = await mealPlanningProvider.GetTargetsAsync(userId, cancellationToken);

            // Auto-derived targets track the profile (weight/height/age/gender/
            // goal/activity); a manually set target is the user's and is left
            // untouched until they change it themselves.
            if (existing is { IsManualOverride: true })
            {
                return existing;
            }

            return await SeedTargetsFromProfileAsync(userId, profile, cancellationToken);
        });

    public Task<ServiceResult<List<MealSuggestionModel>>> GetSuggestionsAsync(Guid userId, int? month, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var resolvedMonth = month ?? DateTime.UtcNow.Month;
            if (resolvedMonth is < 1 or > 12)
            {
                throw new ValidationException($"Invalid month '{resolvedMonth}'.", "That's not a valid month.");
            }

            var suggestions = await mealPlanningProvider.GetSuggestionsForMonthAsync(resolvedMonth, cancellationToken);

            // The user's targets already encode height/weight/age/gender/goal/
            // activity, so scoring suggestions against them is what makes the
            // library personal without re-deriving the Mifflin-St Jeor math here.
            var targets = await GetOrCreateTargetsAsync(userId, cancellationToken);
            var profile = await userProfileProvider.GetAsync(userId, cancellationToken);

            return MealRecommendationScorer.Rank(suggestions, targets, profile?.Goal);
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
        return await SeedTargetsFromProfileAsync(userId, profile, cancellationToken);
    }

    private async Task<UserNutritionTargetsModel> SeedTargetsFromProfileAsync(Guid userId, UserProfileModel? profile, CancellationToken cancellationToken)
    {
        var request = ComputeInitialTargets(profile);
        request.IsManualOverride = false;

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

        var tdee = (bmr * ActivityMultiplierFor(profile.DailyActivityLevel))
            + WeeklyTrainingCaloriesPerDay(
                profile.TrainingDaysPerWeek, profile.SessionDurationMinutes, weightKg);

        var calorieTarget = profile.Goal switch
        {
            "BuildMuscle" => tdee + 250,
            "LoseFat" => tdee - 500,
            _ => tdee
        };

        // Clamp calories first so the macro split below is derived from the
        // number we actually return and therefore reconciles with it, even for
        // extreme height/weight/age combinations.
        var clampedCalories = Math.Clamp(Math.Round(calorieTarget), 1200, 6000);

        // 2 g/kg protein, fat at 25% of calories, carbs absorb the rest. Protein
        // is capped so it can never crowd out carbs (which would otherwise go
        // negative and leave the macro totals summing above the calorie target).
        var fatsG = Math.Clamp(Math.Round(clampedCalories * 0.25 / 9), 0, 300);
        var proteinBudgetG = Math.Max(clampedCalories - (fatsG * 9), 0) / 4;
        var proteinG = Math.Clamp(Math.Round(Math.Min(weightKg * 2, proteinBudgetG)), 0, 400);
        var carbsG = Math.Clamp(Math.Round(Math.Max((clampedCalories - (proteinG * 4) - (fatsG * 9)) / 4, 0)), 0, 800);

        return new UpsertNutritionTargetsRequest
        {
            TargetCalories = (short)clampedCalories,
            TargetProteinG = (short)proteinG,
            TargetCarbsG = (short)carbsG,
            TargetFatsG = (short)fatsG
        };
    }
}
