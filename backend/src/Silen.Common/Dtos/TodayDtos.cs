namespace Silen.Common.Dtos;

public sealed class LogHydrationRequest
{
    public short AmountMl { get; set; }
}

public sealed class LogBodyweightRequest
{
    public decimal WeightKg { get; set; }
}

public sealed class CompleteWorkoutRequest
{
    public Guid WorkoutSessionId { get; set; }
    public short DurationMinutes { get; set; }
    public short? CaloriesEstimate { get; set; }
    public decimal? RpeScore { get; set; }
    public decimal? TonnageKg { get; set; }
    /// <summary>The set-by-set log behind real Personal Records - null for an older client build.</summary>
    public List<SetLogRequest>? SetLogs { get; set; }
}

public sealed class SetLogRequest
{
    public Guid ExerciseId { get; set; }
    public byte SetNumber { get; set; }
    public decimal WeightKg { get; set; }
    public short Reps { get; set; }
}

/// <summary>
/// Composed by TodayService from Hydration + Bodyweight + Streak + WorkoutSession
/// providers - this is the one fully-wired vertical slice of the app.
/// </summary>
public sealed class TodayDashboardDto
{
    public TodaySessionDto Session { get; set; } = new();
    public List<TargetExerciseDto> TargetExercises { get; set; } = new();
    public int HydrationTotalMl { get; set; }
    public int HydrationTargetMl { get; set; }
    public decimal? LatestWeightKg { get; set; }
    public decimal? WeightDeltaKg { get; set; }
    public int CurrentStreakDays { get; set; }
    public int WeeklyCompliancePercent { get; set; }
    public List<WeekDayStatusDto> WeekStatuses { get; set; } = new();
    public ActiveSplitDto? ActiveSplit { get; set; }
}

public sealed class ActiveSplitDto
{
    public Guid SplitId { get; set; }
    public string? Name { get; set; }
    public byte? DurationDays { get; set; }
    public DateTime ActivatedAtUtc { get; set; }
}

public sealed class TodaySessionDto
{
    public Guid? WorkoutSessionId { get; set; }
    public string Status { get; set; } = "Scheduled";
    public string? Title { get; set; }
    public string? FocusLabel { get; set; }
    public short? EstimatedMinutes { get; set; }
    public bool IsRestDay { get; set; }
}

public sealed class TargetExerciseDto
{
    public Guid ExerciseId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string MuscleGroup { get; set; } = string.Empty;
    public string? EquipmentType { get; set; }
    public string? DemoVideoUrl { get; set; }
    public byte TargetSets { get; set; }
    public byte TargetRepsLow { get; set; }
    public byte TargetRepsHigh { get; set; }
}

public sealed class WeekDayStatusDto
{
    public DateTime Date { get; set; }
    public string Status { get; set; } = "Scheduled";
}

public sealed class LogBodyweightResultDto
{
    public decimal LatestWeightKg { get; set; }
    public decimal? DeltaKg { get; set; }
}

/// <summary>One logged set from a past day's session - see `WorkoutSessionModels.SetLogModel`.</summary>
public sealed class SetLogDto
{
    public Guid ExerciseId { get; set; }
    public string ExerciseName { get; set; } = string.Empty;
    public byte SetNumber { get; set; }
    public decimal WeightKg { get; set; }
    public short Reps { get; set; }
    public DateTime CompletedAtUtc { get; set; }
}
