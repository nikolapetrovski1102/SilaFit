namespace Silen.Common.Models;

public sealed class UserNutritionTargetsModel
{
    public Guid UserId { get; set; }
    public short TargetCalories { get; set; }
    public short TargetProteinG { get; set; }
    public short TargetCarbsG { get; set; }
    public short TargetFatsG { get; set; }
    public DateTime UpdatedAtUtc { get; set; }
}

public sealed class MealLogModel
{
    public Guid MealLogId { get; set; }
    public Guid UserId { get; set; }
    public DateOnly LogDateUtc { get; set; }
    public string MealType { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public short CaloriesKcal { get; set; }
    public short ProteinG { get; set; }
    public short CarbsG { get; set; }
    public short FatsG { get; set; }
    public string Status { get; set; } = "Planned";
    public TimeSpan? PlannedLocalTime { get; set; }
    public DateTime? LoggedAtUtc { get; set; }
    public DateTime CreatedAtUtc { get; set; }
}

/// <summary>A curated meal idea from the seeded dbo.MealSuggestions library -
/// see database/seed/003_SeedMealSuggestions.sql for how the macros were
/// derived from USDA FoodData Central.</summary>
public sealed class MealSuggestionModel
{
    public Guid MealSuggestionId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string MealType { get; set; } = string.Empty;
    public string? Description { get; set; }
    public short CaloriesKcal { get; set; }
    public short ProteinG { get; set; }
    public short CarbsG { get; set; }
    public short FatsG { get; set; }

    /// <summary>1-12, or null when the suggestion is evergreen (shown every month).</summary>
    public byte? SuggestedMonth { get; set; }
    public bool IsSystemDefault { get; set; }
    public int SortOrder { get; set; }
}
