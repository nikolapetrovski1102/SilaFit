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

public sealed class AdminPlanEntitlementsUpsertRequest
{
    public Guid PlanId { get; set; }

    /// <summary>Null means unlimited.</summary>
    public int? MaxActiveSplits { get; set; }

    /// <summary>Null means unlimited.</summary>
    public int? MaxActiveDietPlans { get; set; }

    public bool AllowAiGeneration { get; set; }
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

    /// <summary>'Private' | 'Public' | 'Shared'. Left blank, the service defaults a
    /// new/changed split to Private so a trainer's work is never published by accident.
    /// Ignored on update of someone else's split (the procedure refuses that first).</summary>
    public string Visibility { get; set; } = string.Empty;
}

/// <summary>Trainer hands one split to one app user. SetActive also makes it their program.</summary>
public sealed class AdminSplitAssignRequest
{
    public Guid SplitId { get; set; }
    public Guid UserId { get; set; }
    public bool SetActive { get; set; }
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

public sealed class AdminDietPlanUpsertRequest
{
    public Guid? DietPlanId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? HeroImageUrl { get; set; }

    /// <summary>'Weekly' | 'Monthly'. Display/filter metadata only - the actual cycle length
    /// is <see cref="DurationDays"/>.</summary>
    public string PeriodType { get; set; } = "Weekly";

    /// <summary>1-31. The console does not force this to match the number of days it has.</summary>
    public int DurationDays { get; set; } = 7;

    public int SortOrder { get; set; }

    /// <summary>'Private' | 'Public' | 'Shared'. Left blank, the service defaults a
    /// new/changed plan to Private so a trainer's work is never published by accident.
    /// Ignored on update of someone else's plan (the procedure refuses that first).</summary>
    public string Visibility { get; set; } = string.Empty;
}

/// <summary>Trainer hands one diet plan to one app user. SetActive also makes it their plan.</summary>
public sealed class AdminDietPlanAssignRequest
{
    public Guid DietPlanId { get; set; }
    public Guid UserId { get; set; }
    public bool SetActive { get; set; }
}

public sealed class AdminDietPlanDayUpsertRequest
{
    public Guid? DietPlanDayId { get; set; }
    public Guid DietPlanId { get; set; }
    public int DayIndex { get; set; }
    public string? Title { get; set; }
}

public sealed class AdminDietPlanMealUpsertRequest
{
    public Guid? DietPlanMealId { get; set; }
    public Guid DietPlanDayId { get; set; }
    public string MealType { get; set; } = string.Empty;
    public Guid MealSuggestionId { get; set; }
    public int SortOrder { get; set; }
}

/// <summary>
/// Super-admin only: regenerate one app user's logs with a generated month of
/// history so the monthly overview has something to show. Replaces the user's
/// existing workouts/meals/hydration/bodyweight and grants a yearly subscription.
/// </summary>
public sealed class AdminMockDataRequest
{
    public Guid UserId { get; set; }

    /// <summary>"Advanced" or "Pro" - see Silen.Common.Models.MockDataProfiles.
    /// Blank defaults to Advanced.</summary>
    public string Profile { get; set; } = string.Empty;

    /// <summary>Days of history ending today. Defaults to 30, capped at 365.</summary>
    public int Days { get; set; } = 30;

    /// <summary>Optional RNG seed, for a reproducible run. Null means "any".</summary>
    public int? Seed { get; set; }
}

/// <summary>Result of an image upload - the URL to store back onto whatever field it's for
/// (e.g. a split's HeroImageUrl).</summary>
public sealed class AdminImageUploadResultDto
{
    public required string Url { get; init; }
}
