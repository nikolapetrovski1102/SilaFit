using Silen.Common.Models;
using Silen.Services.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class CalorieTargetMealPlannerTests
{
    private static MealSuggestionModel Meal(string type, int calories, int score = 80) => new()
    {
        MealSuggestionId = Guid.NewGuid(),
        MealType = type,
        CaloriesKcal = (short)calories,
        MatchScore = score
    };

    [Fact]
    public void CompleteSnacks_AddsEnoughSnacksToReachTarget()
    {
        var breakfast = Meal("Breakfast", 450);
        var lunch = Meal("Lunch", 600);
        var dinner = Meal("Dinner", 650);
        var snack = Meal("Snack", 250);
        var meals = new[] { breakfast, lunch, dinner, snack };
        var byId = meals.ToDictionary(meal => meal.MealSuggestionId);

        var result = CalorieTargetMealPlanner.CompleteSnacks(
            2400,
            [breakfast.MealSuggestionId, lunch.MealSuggestionId, dinner.MealSuggestionId],
            [snack.MealSuggestionId],
            byId,
            [snack]);

        Assert.Equal(3, result.Count);
        Assert.True(1700 + result.Sum(id => byId[id].CaloriesKcal) >= 2400);
    }

    [Fact]
    public void CompleteSnacks_DoesNotAddFoodWhenSelectedDayAlreadyMeetsTarget()
    {
        var breakfast = Meal("Breakfast", 650);
        var lunch = Meal("Lunch", 750);
        var dinner = Meal("Dinner", 700);
        var snack = Meal("Snack", 200);
        var meals = new[] { breakfast, lunch, dinner, snack };
        var byId = meals.ToDictionary(meal => meal.MealSuggestionId);

        var result = CalorieTargetMealPlanner.CompleteSnacks(
            2200,
            [breakfast.MealSuggestionId, lunch.MealSuggestionId, dinner.MealSuggestionId],
            [snack.MealSuggestionId],
            byId,
            [snack]);

        Assert.Single(result);
    }

    [Fact]
    public void CompleteSnacks_IgnoresInvalidAiSnackIds()
    {
        var breakfast = Meal("Breakfast", 600);
        var lunch = Meal("Lunch", 700);
        var dinner = Meal("Dinner", 700);
        var snack = Meal("Snack", 250);
        var meals = new[] { breakfast, lunch, dinner, snack };
        var byId = meals.ToDictionary(meal => meal.MealSuggestionId);

        var result = CalorieTargetMealPlanner.CompleteSnacks(
            2200,
            [breakfast.MealSuggestionId, lunch.MealSuggestionId, dinner.MealSuggestionId],
            [Guid.NewGuid(), breakfast.MealSuggestionId],
            byId,
            [snack]);

        Assert.Single(result);
        Assert.Equal(snack.MealSuggestionId, result[0]);
    }
}
