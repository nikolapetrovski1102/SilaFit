namespace Silen.Common.Dtos;

/// <summary>A user building/editing their own split via the in-app builder. Trimmed
/// clone of AdminSplitUpsertRequest - no Visibility/SortOrder, which aren't
/// app-exposed concepts for user-owned splits (see usp_UserSplit_Upsert).</summary>
public sealed class UserSplitUpsertRequest
{
    public Guid? SplitId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Level { get; set; } = string.Empty;

    /// <summary>1-14.</summary>
    public int DurationDays { get; set; }

    public string? Description { get; set; }
    public string? HeroImageUrl { get; set; }
    public string? RecommendedGoal { get; set; }

    /// <summary>Internal-only: never set from client JSON. Silen.Tools.WeeklyPlanGeneration
    /// is the only caller that passes true here (see WeeklyPlanGenerationService).</summary>
    public bool IsAiGenerated { get; set; }
}

public sealed class UserSplitDayUpsertRequest
{
    public Guid? SplitDayId { get; set; }
    public Guid SplitId { get; set; }
    public int DayIndex { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? FocusLabel { get; set; }
    public int EstimatedMinutes { get; set; } = 45;
    public bool IsRestDay { get; set; }
}

public sealed class UserSplitDayExerciseUpsertRequest
{
    public Guid? SplitDayExerciseId { get; set; }
    public Guid SplitDayId { get; set; }
    public Guid ExerciseId { get; set; }
    public int SortOrder { get; set; }
    public int TargetSets { get; set; }
    public int TargetRepsLow { get; set; }
    public int TargetRepsHigh { get; set; }
}
