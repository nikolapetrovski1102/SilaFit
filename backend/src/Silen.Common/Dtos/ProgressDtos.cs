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
