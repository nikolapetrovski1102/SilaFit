using Silen.Common.Models;

namespace Silen.Common.Dtos;

public sealed class DietPlanDetailDto
{
    public DietPlanModel Plan { get; set; } = new();
    public List<DietPlanDayWithMealsDto> Days { get; set; } = new();

    /// <summary>Quantity-aggregated ingredient lines across every meal in the
    /// plan - the week's shopping list. Empty when none of the referenced meal
    /// suggestions have ingredient data (see dbo.MealSuggestionIngredients).</summary>
    public List<string> ShoppingList { get; set; } = new();
}

public sealed class DietPlanDayWithMealsDto
{
    public DietPlanDayModel Day { get; set; } = new();
    public List<DietPlanMealModel> Meals { get; set; } = new();
}

/// <summary>A user building/editing their own diet plan via the in-app builder.
/// Trimmed clone of AdminDietPlanUpsertRequest - no Visibility/SortOrder, which
/// aren't app-exposed concepts for user-owned plans (see usp_UserDietPlan_Upsert).</summary>
public sealed class UserDietPlanUpsertRequest
{
    public Guid? DietPlanId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? HeroImageUrl { get; set; }
    public string PeriodType { get; set; } = "Weekly";
    public int DurationDays { get; set; } = 7;

    /// <summary>Internal-only: never set from client JSON. Silen.Tools.WeeklyPlanGeneration
    /// is the only caller that passes true here (see WeeklyPlanGenerationService).</summary>
    public bool IsAiGenerated { get; set; }
}

public sealed class UserDietPlanDayUpsertRequest
{
    public Guid? DietPlanDayId { get; set; }
    public Guid DietPlanId { get; set; }
    public int DayIndex { get; set; }
    public string? Title { get; set; }
}

public sealed class UserDietPlanMealUpsertRequest
{
    public Guid? DietPlanMealId { get; set; }
    public Guid DietPlanDayId { get; set; }
    public string MealType { get; set; } = string.Empty;
    public Guid MealSuggestionId { get; set; }
    public int SortOrder { get; set; }
}
