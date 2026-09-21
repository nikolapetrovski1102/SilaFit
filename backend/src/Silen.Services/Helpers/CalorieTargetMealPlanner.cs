using Silen.Common.Models;

namespace Silen.Services.Helpers;

/// <summary>
/// Completes an AI-selected day with additional snack meals until the user's
/// calorie target is reached. The language model chooses the food pattern;
/// this deterministic guard makes the numeric promise reliable.
/// </summary>
public static class CalorieTargetMealPlanner
{
    public static List<Guid> CompleteSnacks(
        int targetCalories,
        IReadOnlyList<Guid> mainMealIds,
        IReadOnlyList<Guid> selectedSnackIds,
        IReadOnlyDictionary<Guid, MealSuggestionModel> mealById,
        IReadOnlyList<MealSuggestionModel> snackCandidates)
    {
        var snacks = selectedSnackIds
            .Where(id => mealById.TryGetValue(id, out var meal)
                         && meal.CaloriesKcal > 0
                         && string.Equals(meal.MealType, "Snack", StringComparison.OrdinalIgnoreCase))
            .ToList();

        var calories = mainMealIds
            .Concat(snacks)
            .Where(mealById.ContainsKey)
            .Sum(id => (int)mealById[id].CaloriesKcal);

        if (targetCalories <= 0 || calories >= targetCalories)
        {
            return snacks;
        }

        var candidates = snackCandidates
            .Where(meal => meal.CaloriesKcal > 0)
            .OrderByDescending(meal => meal.MatchScore)
            .ThenBy(meal => meal.SortOrder)
            .ToList();
        if (candidates.Count == 0)
        {
            throw new InvalidOperationException("A calorie target cannot be completed without a positive-calorie snack.");
        }

        var usage = snacks.GroupBy(id => id).ToDictionary(group => group.Key, group => group.Count());
        while (calories < targetCalories)
        {
            var gap = targetCalories - calories;
            var chosen = candidates
                .OrderBy(meal => Math.Abs(meal.CaloriesKcal - gap))
                .ThenBy(meal => usage.GetValueOrDefault(meal.MealSuggestionId))
                .ThenByDescending(meal => meal.MatchScore)
                .First();

            snacks.Add(chosen.MealSuggestionId);
            usage[chosen.MealSuggestionId] = usage.GetValueOrDefault(chosen.MealSuggestionId) + 1;
            calories += chosen.CaloriesKcal;
        }

        return snacks;
    }
}
