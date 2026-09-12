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

    /// <summary>The UserProfiles.Goal value ('BuildMuscle'/'LoseFat'/'MaintainActive') this split
    /// best serves, or null if it isn't goal-tagged. Set from the WorkoutSplits row.</summary>
    public string? RecommendedGoal { get; set; }

    /// <summary>Computed by SplitService from the caller's own profile goal, not a DB column -
    /// true when RecommendedGoal matches the authenticated user's onboarding goal.</summary>
    public bool MatchesGoal { get; set; }
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
