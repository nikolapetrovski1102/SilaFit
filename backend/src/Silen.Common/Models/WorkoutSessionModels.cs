namespace Silen.Common.Models;

public sealed class TodaySessionModel
{
    public Guid WorkoutSessionId { get; set; }
    public string Status { get; set; } = "Scheduled";
    public DateTime ScheduledDateUtc { get; set; }
    public Guid? SplitDayId { get; set; }
    public string? Title { get; set; }
    public string? FocusLabel { get; set; }
    public short? EstimatedMinutes { get; set; }
    public bool? IsRestDay { get; set; }
}

public sealed class TargetExerciseModel
{
    public Guid ExerciseId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string MuscleGroup { get; set; } = string.Empty;
    public string? EquipmentType { get; set; }
    public string? DemoVideoUrl { get; set; }
    public byte SortOrder { get; set; }
    public byte TargetSets { get; set; }
    public byte TargetRepsLow { get; set; }
    public byte TargetRepsHigh { get; set; }
}

public sealed class WorkoutSessionCompletionModel
{
    public Guid WorkoutSessionId { get; set; }
    public string Status { get; set; } = "Completed";
    public DateTime? CompletedAtUtc { get; set; }
    public short? DurationMinutes { get; set; }
    public short? CaloriesEstimate { get; set; }
    public decimal? RpeScore { get; set; }
    public decimal? TonnageKg { get; set; }
}

public sealed class RangeSummaryModel
{
    public int CompletedSessions { get; set; }
    public int ScheduledSessions { get; set; }
    public decimal TotalTonnageKg { get; set; }
    public decimal AvgRpe { get; set; }
}

public sealed class DaySessionStatusModel
{
    public DateTime ScheduledDateUtc { get; set; }
    public string Status { get; set; } = string.Empty;
    public decimal? TonnageKg { get; set; }
    public decimal? RpeScore { get; set; }
}

/// <summary>One logged set, as sent from the active workout tracker on completion.</summary>
public sealed class SetLogEntryModel
{
    public Guid ExerciseId { get; set; }
    public byte SetNumber { get; set; }
    public decimal WeightKg { get; set; }
    public short Reps { get; set; }
}

/// <summary>
/// The heaviest set ever logged for one exercise, plus the heaviest set
/// before it (null if this is the only set ever logged for that exercise) -
/// see `usp_WorkoutSession_GetPersonalRecords`.
/// </summary>
public sealed class PersonalRecordModel
{
    public Guid ExerciseId { get; set; }
    public string ExerciseName { get; set; } = string.Empty;
    public decimal WeightKg { get; set; }
    public short Reps { get; set; }
    public DateTime AchievedAtUtc { get; set; }
    public decimal? PreviousBestWeightKg { get; set; }
}
