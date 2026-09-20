namespace Silen.Common.Models;

public sealed class UserNutritionTargetsModel
{
    public Guid UserId { get; set; }
    public short TargetCalories { get; set; }
    public short TargetProteinG { get; set; }
    public short TargetCarbsG { get; set; }
    public short TargetFatsG { get; set; }

    /// <summary>True when the user set these targets themselves; false when they
    /// were derived from the profile. Auto targets get recomputed when the profile
    /// changes, manual ones are left alone.</summary>
    public bool IsManualOverride { get; set; }

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

    /// <summary>True when at least one dbo.MealSuggestionIngredients row exists for this
    /// suggestion, so it can back a real shopping list. Only ingredient-backed meals are
    /// offered to the weekly plan generator as diet-plan candidates.</summary>
    public bool HasIngredients { get; set; }

    /// <summary>Compact, ordered preview of at most four ingredient lines. This
    /// gives the weekly AI review enough food-composition context without sending
    /// or rendering the full recipe.</summary>
    public string? IngredientPreview { get; set; }

    /// <summary>Total ingredient-line count, used to append a concise "+N more"
    /// indicator when <see cref="IngredientPreview"/> is truncated.</summary>
    public int IngredientCount { get; set; }

    /// <summary>1-12, or null when the suggestion is evergreen (shown every month).</summary>
    public byte? SuggestedMonth { get; set; }
    public bool IsSystemDefault { get; set; }
    public int SortOrder { get; set; }

    /// <summary>Computed by MealPlanningService from the caller's nutrition targets (which
    /// derive from their profile), not a DB column. 0-100, higher is a better fit.</summary>
    public int MatchScore { get; set; }

    /// <summary>Plain-language explanation of <see cref="MatchScore"/>, shown in the UI.</summary>
    public string? MatchReason { get; set; }
}
