using Silen.Common.Models;

namespace Silen.Services.Helpers;

/// <summary>
/// Scores curated meal suggestions against one user's daily nutrition targets.
/// Those targets are already derived from height/weight/age/gender/goal (see
/// <see cref="Implementations.MealPlanningService"/>'s Mifflin-St Jeor
/// estimate), so scoring against them is how the person data reaches the meal
/// library - without duplicating that math here.
///
/// Each meal is compared with the share of the day its slot typically fills:
///  - calorie fit - sitting near that slot's slice of the daily target
///  - protein fit - closing the target's protein share without overshooting
///  - goal nudge  - a deficit target favors lighter meals, a surplus favors
///                  more protein-dense ones
/// </summary>
public static class MealRecommendationScorer
{
    private static readonly Dictionary<string, double> SlotShares = new()
    {
        ["Breakfast"] = 0.25,
        ["Lunch"] = 0.30,
        ["Dinner"] = 0.30,
        ["Snack"] = 0.15
    };

    // No ordinary meal clears ~35% of its own calories from protein, so above
    // this a low-calorie target's protein share stops being a useful bar - see
    // its use in Score() below.
    private const double MaxScoredProteinShare = 0.35;

    /// <summary>
    /// Scores every suggestion in place (<see cref="MealSuggestionModel.MatchScore"/>/
    /// <see cref="MealSuggestionModel.MatchReason"/>) and returns them best-first,
    /// with curated SortOrder only as a tie-break.
    /// </summary>
    public static List<MealSuggestionModel> Rank(
        IReadOnlyList<MealSuggestionModel> suggestions,
        UserNutritionTargetsModel targets,
        string? goal)
    {
        foreach (var suggestion in suggestions)
        {
            var (score, reason) = Score(suggestion, targets, goal);
            suggestion.MatchScore = score;
            suggestion.MatchReason = reason;
        }

        return suggestions
            .OrderByDescending(s => s.MatchScore)
            .ThenBy(s => s.SortOrder)
            .ToList();
    }

    private static (int Score, string Reason) Score(
        MealSuggestionModel suggestion,
        UserNutritionTargetsModel targets,
        string? goal)
    {
        var slotShare = SlotShares.GetValueOrDefault(suggestion.MealType, 0.25);
        var slotCalories = Math.Max(targets.TargetCalories * slotShare, 250);

        var calorieFit = Clamp01(1 - Math.Abs(suggestion.CaloriesKcal - slotCalories) / slotCalories);

        var targetProteinShare = targets.TargetCalories <= 0
            ? 0.25
            : (double)targets.TargetProteinG * 4 / targets.TargetCalories;
        // Capped so a low-calorie target (e.g. a sedentary Lose Fat plan clamped
        // to the 1200 kcal floor) can't push the denominator past what any real
        // meal's protein density could realistically match - past this point
        // every suggestion would score as protein-poor no matter how lean it is.
        var cappedTargetProteinShare = Math.Min(targetProteinShare, MaxScoredProteinShare);
        var suggestionProteinShare = suggestion.CaloriesKcal <= 0
            ? 0
            : (double)suggestion.ProteinG * 4 / suggestion.CaloriesKcal;
        var proteinFit = Clamp01(suggestionProteinShare / Math.Max(cappedTargetProteinShare, 0.10));

        var goalNudge = goal switch
        {
            // A deficit target rewards meals that stay under the slot's calories.
            "LoseFat" => Clamp01((slotCalories - suggestion.CaloriesKcal) / slotCalories) * 0.5,
            // A surplus target rewards protein density, not just more calories.
            "BuildMuscle" => proteinFit * 0.5,
            _ => 0
        };

        var combined = Clamp01((calorieFit * 0.55) + (proteinFit * 0.35) + (goalNudge * 0.10));
        var score = (int)Math.Round(combined * 100);
        return (score, BuildReason(suggestion, targets, goal, calorieFit, proteinFit, slotCalories));
    }

    private static string BuildReason(
        MealSuggestionModel suggestion,
        UserNutritionTargetsModel targets,
        string? goal,
        double calorieFit,
        double proteinFit,
        double slotCalories)
    {
        if (proteinFit >= 0.85 && targets.TargetProteinG > 0)
        {
            return $"High protein toward your {targets.TargetProteinG}g target";
        }

        if (goal == "LoseFat" && suggestion.CaloriesKcal <= slotCalories)
        {
            return "Light enough for your fat-loss plan";
        }

        if (calorieFit >= 0.8)
        {
            // Quote the meal's own calories, not the slot target - the two are
            // close whenever this branch fires, but showing the target next to
            // a differently-sized meal reads as a mismatch on the card.
            return $"{suggestion.CaloriesKcal} kcal - fits your {suggestion.MealType.ToLowerInvariant()} target";
        }

        return $"Balances your {(int)targets.TargetCalories} kcal day";
    }

    private static double Clamp01(double value) => Math.Clamp(value, 0, 1);
}
