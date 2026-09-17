namespace Silen.Common.Dtos;

/// <summary>Result of one run of the weekly AI plan-generation batch - the weekly
/// counterpart of <see cref="MonthlyReviewSummaryDto"/>.</summary>
public sealed class WeeklyPlanGenerationSummaryDto
{
    public Guid RunId { get; set; }
    public DateTime WeekStartUtc { get; set; }
    public bool DryRun { get; set; }
    public bool EmailsEnabled { get; set; }
    public bool PushEnabled { get; set; }
    public int UsersConsidered { get; set; }
    public int PlansGenerated { get; set; }
    public int NotificationsSent { get; set; }
    public int Skipped { get; set; }
    public int Failures { get; set; }
    public List<WeeklyPlanGenerationFailureDto> FailureDetails { get; set; } = new();
    public DateTime StartedAtUtc { get; set; }
    public DateTime CompletedAtUtc { get; set; }
}

public sealed class WeeklyPlanGenerationFailureDto
{
    public Guid UserId { get; set; }
    public string? Email { get; set; }
    public string Message { get; set; } = string.Empty;
}
