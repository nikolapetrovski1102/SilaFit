namespace Silen.Common.Models;

/// <summary>App-facing diet plan - the meal-planning equivalent of <see cref="WorkoutSplitModel"/>,
/// field-for-field mirroring its ownership/visibility shape.</summary>
public sealed class DietPlanModel
{
    public Guid DietPlanId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? HeroImageUrl { get; set; }
    public string PeriodType { get; set; } = "Weekly";
    public byte DurationDays { get; set; }
    public bool IsSystemDefault { get; set; }
    public int SortOrder { get; set; }

    /// <summary>Who may see this plan in the app: 'Public' (everyone), 'Shared'
    /// (assigned users only) or 'Private' (its owner only). The app-side list and
    /// detail procedures have already filtered on it, so every plan returned to a
    /// user is one they are allowed to see.</summary>
    public string Visibility { get; set; } = "Public";

    /// <summary>Set from the DietPlans row when the caller built this plan themselves
    /// via the in-app builder. Not serialized to the client directly -
    /// <see cref="IsEditableByMe"/> is what the API exposes.</summary>
    public Guid? OwnerUserId { get; set; }

    /// <summary>Computed by DietPlanService: true only when OwnerUserId matches the
    /// authenticated caller. Trainer-assigned and system plans are never editable,
    /// regardless of who is asking.</summary>
    public bool IsEditableByMe { get; set; }

    /// <summary>True when Silen.Tools.WeeklyPlanGeneration wrote this plan rather than the
    /// user building it by hand (see 051_WeeklyAiPlans.sql).</summary>
    public bool IsAiGenerated { get; set; }

    /// <summary>Null while this AI-generated plan is still eligible to be overwritten by
    /// next Sunday's run; set once the user taps "Keep this plan". Always null for a
    /// non-AI-generated plan.</summary>
    public DateTime? AiKeptAtUtc { get; set; }
}

public sealed class DietPlanDayModel
{
    public Guid DietPlanDayId { get; set; }
    public byte DayIndex { get; set; }
    public string? Title { get; set; }
}

/// <summary>One meal slot within a diet-plan day, carrying the referenced
/// MealSuggestions row's fields so the client can render it without a second lookup.</summary>
public sealed class DietPlanMealModel
{
    public Guid DietPlanDayId { get; set; }
    public Guid DietPlanMealId { get; set; }
    public string MealType { get; set; } = string.Empty;
    public Guid MealSuggestionId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }
    public short CaloriesKcal { get; set; }
    public short ProteinG { get; set; }
    public short CarbsG { get; set; }
    public short FatsG { get; set; }
    public int SortOrder { get; set; }
}

public sealed class ActiveDietPlanModel
{
    public Guid UserId { get; set; }
    public Guid DietPlanId { get; set; }
    public DateTime ActivatedAtUtc { get; set; }
    public string? Name { get; set; }
    public byte? DurationDays { get; set; }
}
