namespace Silen.Common.Dtos;

/// <summary>
/// Request bodies for the console's content editors. The service layer validates
/// these (blank names, out-of-range months, unknown enum values) before the
/// procedure runs, so a rejected edit comes back as a 400 with a sentence rather
/// than a constraint violation.
/// </summary>
public sealed class AdminExerciseUpsertRequest
{
    /// <summary>Null on create, the existing id on update.</summary>
    public Guid? ExerciseId { get; set; }

    public string Name { get; set; } = string.Empty;
    public string MuscleGroup { get; set; } = string.Empty;
    public string? EquipmentType { get; set; }
    public bool IsCompound { get; set; }
    public string? DemoVideoUrl { get; set; }
}

public sealed class AdminMealSuggestionUpsertRequest
{
    public Guid? MealSuggestionId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string MealType { get; set; } = string.Empty;
    public string? Description { get; set; }
    public int CaloriesKcal { get; set; }
    public int ProteinG { get; set; }
    public int CarbsG { get; set; }
    public int FatsG { get; set; }

    /// <summary>1-12, or null for a suggestion that is not tied to a month.</summary>
    public int? SuggestedMonth { get; set; }

    public int SortOrder { get; set; }
}

public sealed class AdminPlanUpsertRequest
{
    public Guid? PlanId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Tagline { get; set; }
    public decimal MonthlyPrice { get; set; }
    public decimal YearlyPrice { get; set; }
    public bool IsFeatured { get; set; }
    public int SortOrder { get; set; }
}

public sealed class AdminPlanFeatureUpsertRequest
{
    public Guid? PlanFeatureId { get; set; }
    public Guid PlanId { get; set; }
    public string FeatureText { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public bool IsHighlighted { get; set; }
}

public sealed class AdminSplitUpsertRequest
{
    public Guid? SplitId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Level { get; set; } = string.Empty;

    /// <summary>1-14. The console does not force this to match the number of days it has.</summary>
    public int DurationDays { get; set; }

    public string? Description { get; set; }
    public string? HeroImageUrl { get; set; }
    public string? RecommendedGoal { get; set; }
    public int SortOrder { get; set; }
}

public sealed class AdminSplitDayUpsertRequest
{
    public Guid? SplitDayId { get; set; }
    public Guid SplitId { get; set; }
    public int DayIndex { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? FocusLabel { get; set; }
    public int EstimatedMinutes { get; set; } = 45;
    public bool IsRestDay { get; set; }
}

public sealed class AdminSplitDayExerciseUpsertRequest
{
    public Guid? SplitDayExerciseId { get; set; }
    public Guid SplitDayId { get; set; }
    public Guid ExerciseId { get; set; }
    public int SortOrder { get; set; }
    public int TargetSets { get; set; }
    public int TargetRepsLow { get; set; }
    public int TargetRepsHigh { get; set; }
}
