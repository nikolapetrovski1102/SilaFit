namespace Silen.Common.Models;

/// <summary>Every real number AnalyticsService substitutes into the AiPromptTemplates row's {{Placeholder}} tokens.</summary>
public sealed class MonthlySnapshotModel
{
    public bool RealDataOnly { get; set; }
    public int RecapVersion { get; set; }
    public int MissedWorkoutDays { get; set; }
    public int? DaysOverCalorieTarget { get; set; }
    public int? TotalCaloriesOverTarget { get; set; }
    public List<MonthlyExerciseModel> Exercises { get; set; } = new();
    public string DisplayName { get; set; } = string.Empty;
    public int CompletedSessions { get; set; }
    public int ScheduledSessions { get; set; }
    public decimal TotalTonnageKg { get; set; }
    public decimal AvgRpe { get; set; }
    public int CurrentStreakDays { get; set; }
    public int WeeklyCompliancePercent { get; set; }
    public decimal? StartWeightKg { get; set; }
    public decimal? EndWeightKg { get; set; }
    public int LoggedMealDays { get; set; }
    public int TotalDaysInRange { get; set; }
    public decimal? AvgCaloriesLogged { get; set; }
    public short? TargetCalories { get; set; }
}

public sealed class AiPromptTemplateModel
{
    public Guid PromptTemplateId { get; set; }
    public string TemplateKey { get; set; } = string.Empty;
    public string SystemPrompt { get; set; } = string.Empty;
    public string UserPromptTemplate { get; set; } = string.Empty;
    public string Model { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public DateTime UpdatedAtUtc { get; set; }
}

public sealed class MonthlyAnalyticsReportModel
{
    public Guid ReportId { get; set; }
    public Guid UserId { get; set; }
    public int ReportYear { get; set; }
    public int ReportMonth { get; set; }
    public string SnapshotJson { get; set; } = string.Empty;
    public string ResultJson { get; set; } = string.Empty;
    public DateTime GeneratedAtUtc { get; set; }
}

/// <summary>The weekly equivalent of <see cref="MonthlyAnalyticsReportModel"/> - cached/audited AI
/// reports keyed by ISO year + week instead of calendar year + month.</summary>
public sealed class WeeklyAnalyticsReportModel
{
    public Guid ReportId { get; set; }
    public Guid UserId { get; set; }
    public int ReportYear { get; set; }
    public int ReportWeek { get; set; }
    public string SnapshotJson { get; set; } = string.Empty;
    public string ResultJson { get; set; } = string.Empty;
    public DateTime GeneratedAtUtc { get; set; }
}

/// <summary>Heaviest logged set per completed session; record is bounded by report end.</summary>
public sealed class MonthlyExerciseModel
{
    public Guid ExerciseId { get; set; }
    public string ExerciseName { get; set; } = string.Empty;
    public decimal RecordWeightKg { get; set; }
    public List<MonthlyExercisePointModel> Points { get; set; } = new();
}

public sealed class MonthlyExercisePointModel
{
    public DateTime DateUtc { get; set; }
    public decimal WeightKg { get; set; }
    public short Reps { get; set; }
    public decimal? SessionRpe { get; set; }
}
