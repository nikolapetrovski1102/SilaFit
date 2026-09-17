namespace Silen.Common.Models;

/// <summary>One execution of the weekly AI plan-generation batch, as recorded in
/// dbo.WeeklyAiPlanRuns - the weekly counterpart of <see cref="MonthlyReviewRunModel"/>.</summary>
public sealed class WeeklyAiPlanRunModel
{
    public Guid RunId { get; set; }
    public DateTime WeekStartUtc { get; set; }
    public string Status { get; set; } = string.Empty;
    public int UsersConsidered { get; set; }
    public int PlansGenerated { get; set; }
    public int NotificationsSent { get; set; }
    public int Failures { get; set; }
    public DateTime StartedAtUtc { get; set; }
    public DateTime? CompletedAtUtc { get; set; }
}

/// <summary>Per-user outcome recorded in dbo.WeeklyAiPlanDeliveries. Split and diet
/// generation succeed or fail independently, so each gets its own status/id.</summary>
public sealed class WeeklyAiPlanDeliveryModel
{
    public Guid RunId { get; set; }
    public Guid UserId { get; set; }
    public DateTime WeekStartUtc { get; set; }
    public string SplitStatus { get; set; } = string.Empty;
    public string DietStatus { get; set; } = string.Empty;
    public Guid? SplitId { get; set; }
    public Guid? DietPlanId { get; set; }
    public string? ErrorMessage { get; set; }
    public DateTime? GeneratedAtUtc { get; set; }
    public DateTime? NotifiedAtUtc { get; set; }
}

/// <summary>Delivery/run status values shared by both procedures.</summary>
public static class WeeklyAiPlanStatuses
{
    public const string Generated = "Generated";
    public const string Skipped = "Skipped";
    public const string Failed = "Failed";
}
