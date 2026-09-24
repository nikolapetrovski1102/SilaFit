namespace Silen.Common.Dtos;

/// <summary>
/// Composed by ProgressService: real numbers from logged data plus a
/// rule-based (template-driven, no external AI call) narrative summary.
/// </summary>
public sealed class ProgressOverviewDto
{
    public int CurrentStreakDays { get; set; }
    public int WeeklyCompliancePercent { get; set; }
    public int CompletedSessions { get; set; }
    public int ScheduledSessions { get; set; }
    public decimal TotalTonnageKg { get; set; }
    public decimal AvgRpe { get; set; }
    public List<HeatmapDayDto> Heatmap { get; set; } = new();
    public List<string> Insights { get; set; } = new();
}

public sealed class HeatmapDayDto
{
    public DateTime Date { get; set; }
    public string Status { get; set; } = "Scheduled";
    public decimal? TonnageKg { get; set; }
    public decimal? RpeScore { get; set; }
}

/// <summary>
/// The heaviest set ever logged for one exercise. `PreviousBestWeightKg` is
/// null when this is the only set ever logged for that exercise - the
/// client shows no delta badge in that case rather than a misleading "+0".
/// </summary>
public sealed class PersonalRecordDto
{
    public Guid ExerciseId { get; set; }
    public string ExerciseName { get; set; } = string.Empty;
    public decimal WeightKg { get; set; }
    public short Reps { get; set; }
    public DateTime AchievedAtUtc { get; set; }
    public decimal? PreviousBestWeightKg { get; set; }
}

/// <summary>An exercise the caller has logged at least one set for - the Progress screen's exercise picker.</summary>
public sealed class TrackedExerciseDto
{
    public Guid ExerciseId { get; set; }
    public string ExerciseName { get; set; } = string.Empty;
    public int SessionCount { get; set; }
    public DateTime LastTrainedAtUtc { get; set; }
}

/// <summary>Per-session history of one exercise over the requested range, oldest first.</summary>
public sealed class ExerciseProgressDto
{
    public Guid ExerciseId { get; set; }
    public int Days { get; set; }
    public List<ExerciseProgressPointDto> Points { get; set; } = new();
}

public sealed class ExerciseProgressPointDto
{
    public DateTime Date { get; set; }
    public decimal TopWeightKg { get; set; }
    public short TopSetReps { get; set; }
    public decimal EstimatedOneRmKg { get; set; }
    public decimal TotalVolumeKg { get; set; }
    public int TotalReps { get; set; }
    public int SetCount { get; set; }
}
