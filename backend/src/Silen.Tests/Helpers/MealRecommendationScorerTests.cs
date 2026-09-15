using Silen.Common.Models;
using Silen.Services.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class MealRecommendationScorerTests
{
    private static UserNutritionTargetsModel Targets(short calories, short proteinG) => new()
    {
        TargetCalories = calories,
        TargetProteinG = proteinG
    };

    private static MealSuggestionModel Meal(string mealType, short calories, short proteinG, int sortOrder = 0) => new()
    {
        MealSuggestionId = Guid.NewGuid(),
        Title = "Test meal",
        MealType = mealType,
        CaloriesKcal = calories,
        ProteinG = proteinG,
        SortOrder = sortOrder
    };

    [Fact]
    public void Score_ExactSlotAndProteinMatch_ScoresNearPerfect()
    {
        // 2000 kcal / 150g protein target => protein share 0.30, well under the
        // 0.35 cap, so this case is unaffected by the low-calorie cap fix and
        // isolates the base calorie/protein/goal formula.
        var targets = Targets(2000, 150);
        var lunch = Meal("Lunch", 600, 45); // slot share .30 -> slotCalories 600, exact match

        var ranked = MealRecommendationScorer.Rank([lunch], targets, "BuildMuscle");

        Assert.Equal(95, ranked[0].MatchScore);
        Assert.Equal("High protein toward your 150g target", ranked[0].MatchReason);
    }

    [Fact]
    public void Reason_QuotesTheMealsOwnCalories_NotTheSlotTarget()
    {
        // Regression test: the reason string used to quote the slot target
        // (750 kcal here) even when the meal itself was a different size,
        // which read as a mismatch against the card's own calorie count.
        var targets = Targets(3000, 160);
        var breakfast = Meal("Breakfast", 780, 30); // slot target is 750, meal is 780

        var ranked = MealRecommendationScorer.Rank([breakfast], targets, null);

        Assert.Equal("780 kcal - fits your breakfast target", ranked[0].MatchReason);
        Assert.DoesNotContain("750", ranked[0].MatchReason);
    }

    [Fact]
    public void ProteinFit_IsCapped_SoALowCalorieFloorDoesNotMakeEveryMealLookProteinPoor()
    {
        // 1200 kcal (the clamp floor) / 130g protein => raw protein share is
        // 43.3%, which essentially no real meal clears. Capped at 35%, a
        // reasonably lean lunch should still register as "high protein".
        var targets = Targets(1200, 130);
        var lunch = Meal("Lunch", 300, 25); // slot share .30 -> slotCalories 360

        var ranked = MealRecommendationScorer.Rank([lunch], targets, "LoseFat");

        Assert.Equal(80, ranked[0].MatchScore);
        Assert.Equal("High protein toward your 130g target", ranked[0].MatchReason);
    }

    [Fact]
    public void GoalNudge_LoseFat_RewardsStayingUnderSlotCalories()
    {
        var targets = Targets(2000, 120); // protein share .24, no cap involved
        var lighter = Meal("Dinner", 500, 30); // under the 600 kcal slot
        var heavier = Meal("Dinner", 700, 30); // over the 600 kcal slot, same distance

        var ranked = MealRecommendationScorer.Rank([heavier, lighter], targets, "LoseFat");

        Assert.Equal(lighter.MealSuggestionId, ranked[0].MealSuggestionId);
        Assert.True(ranked[0].MatchScore > ranked[1].MatchScore);
    }

    [Fact]
    public void Rank_TiesBreakOnCuratedSortOrder()
    {
        var targets = Targets(2000, 150);
        var second = Meal("Snack", 200, 10, sortOrder: 2);
        var first = Meal("Snack", 200, 10, sortOrder: 1);

        var ranked = MealRecommendationScorer.Rank([second, first], targets, null);

        Assert.Equal(first.MealSuggestionId, ranked[0].MealSuggestionId);
        Assert.Equal(second.MealSuggestionId, ranked[1].MealSuggestionId);
    }

    [Fact]
    public void Score_NeverThrowsOrGoesOutOfRange_ForZeroCalorieEdgeCases()
    {
        var targets = new UserNutritionTargetsModel { TargetCalories = 0, TargetProteinG = 0 };
        var zeroCalMeal = Meal("Snack", 0, 0);

        var ranked = MealRecommendationScorer.Rank([zeroCalMeal], targets, "BuildMuscle");

        Assert.InRange(ranked[0].MatchScore, 0, 100);
    }
}
