namespace Silen.Common.Dtos;

/// <summary>
/// The monthly AI analytics report the frontend maps. Summary is real logged data;
/// Strengths/Improvements/FocusForNextMonth are the AI's written response - its raw JSON
/// deserializes straight into the AI-authored fields below (see AnalyticsService), matching
/// the response_format.json_schema sent to OpenRouter field-for-field.
/// </summary>
public sealed class MonthlyAnalyticsDto
{
    public int Year { get; set; }
    public int Month { get; set; }
    public MonthlyAnalyticsSummaryDto Summary { get; set; } = new();
    public List<string> Strengths { get; set; } = new();
    public List<AnalyticsImprovementDto> Improvements { get; set; } = new();
    public string FocusForNextMonth { get; set; } = string.Empty;
    public DateTime GeneratedAtUtc { get; set; }
}

/// <summary>Real numbers from logged data - never written by the AI, always sourced from MonthlySnapshotModel.</summary>
public sealed class MonthlyAnalyticsSummaryDto
{
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
}

public sealed class AnalyticsImprovementDto
{
    public string Area { get; set; } = string.Empty;
    public string Recommendation { get; set; } = string.Empty;
    public string Priority { get; set; } = "Medium";
}

/// <summary>The exact shape OpenRouter's response_format.json_schema enforces - the AI's raw
/// JSON content deserializes straight into this, no manual re-mapping.</summary>
public sealed class AiAnalyticsResultDto
{
    public List<string> Strengths { get; set; } = new();
    public List<AnalyticsImprovementDto> Improvements { get; set; } = new();
    public string FocusForNextMonth { get; set; } = string.Empty;
}
