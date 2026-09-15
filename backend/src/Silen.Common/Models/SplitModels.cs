namespace Silen.Common.Models;

public sealed class WorkoutSplitModel
{
    public Guid SplitId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Level { get; set; } = string.Empty;
    public byte DurationDays { get; set; }
    public string? Description { get; set; }
    public string? HeroImageUrl { get; set; }
    public bool IsSystemDefault { get; set; }
    public int SortOrder { get; set; }

    /// <summary>Who may see this split in the app: 'Public' (everyone), 'Shared'
    /// (assigned users only) or 'Private' (its owner only). The app-side list and
    /// detail procedures have already filtered on it, so every split returned to a
    /// user is one they are allowed to see.</summary>
    public string Visibility { get; set; } = "Public";

    /// <summary>The UserProfiles.Goal value ('BuildMuscle'/'LoseFat'/'MaintainActive') this split
    /// best serves, or null if it isn't goal-tagged. Set from the WorkoutSplits row.</summary>
    public string? RecommendedGoal { get; set; }

    /// <summary>Computed by SplitService from the caller's own profile goal, not a DB column -
    /// true when RecommendedGoal matches the authenticated user's onboarding goal.</summary>
    public bool MatchesGoal { get; set; }

    /// <summary>Computed by SplitService from the caller's profile (goal + age/BMI-derived level
    /// fit + category affinity), not a DB column. Higher is a better match.</summary>
    public int MatchScore { get; set; }

    /// <summary>Plain-language explanation of <see cref="MatchScore"/>, shown in the UI.</summary>
    public string? MatchReason { get; set; }

    /// <summary>Average training-day length from the split's days (DB aggregate, rest days
    /// excluded), used to fit the user's session-duration answer. 0 when the split has no days
    /// scheduled yet or the database hasn't been migrated to emit it.</summary>
    public int AvgSessionMinutes { get; set; }
    public byte? DaysPerWeek { get; set; }
    public short? ProgramDurationWeeks { get; set; }
    public short? MinSessionMinutes { get; set; }
    public short? MaxSessionMinutes { get; set; }
    public string? EquipmentRequired { get; set; }
    public string? TargetGender { get; set; }
    public string? WorkoutTypeLabel { get; set; }
    public string? SourceCategoriesJson { get; set; }
}

public sealed class SplitDayModel
{
    public Guid SplitDayId { get; set; }
    public byte DayIndex { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? FocusLabel { get; set; }
    public short EstimatedMinutes { get; set; }
    public bool IsRestDay { get; set; }
}

public sealed class SplitDayExerciseModel
{
    public Guid SplitDayId { get; set; }
    public Guid ExerciseId { get; set; }
    public string Name { get; set; } = string.Empty;
    public byte SortOrder { get; set; }
    public byte TargetSets { get; set; }
    public byte TargetRepsLow { get; set; }
    public byte TargetRepsHigh { get; set; }
}

public sealed class ActiveSplitModel
{
    public Guid UserId { get; set; }
    public Guid SplitId { get; set; }
    public DateTime ActivatedAtUtc { get; set; }
    public string? Name { get; set; }
    public byte? DurationDays { get; set; }

    /// <summary>True when this split was picked by the recommender rather than
    /// the user themselves - only a split still flagged this way is ever
    /// revisited by a later auto-assign re-check.</summary>
    public bool IsAutoAssigned { get; set; }
}

public sealed class ExerciseModel
{
    public Guid ExerciseId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string MuscleGroup { get; set; } = string.Empty;
    public string? EquipmentType { get; set; }
    public bool IsCompound { get; set; }
    public string? DemoVideoUrl { get; set; }
}
