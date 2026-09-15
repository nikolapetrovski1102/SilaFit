namespace Silen.Common.Dtos;

/// <summary>Which pass of the monthly review batch a summary describes.</summary>
public static class MonthlyReviewAudiences
{
    /// <summary>Active PRO/ADVANCED subscribers - full AI report by email.</summary>
    public const string Subscribers = "Subscribers";

    /// <summary>Non-paying users - stats teaser + upgrade CTA by email.</summary>
    public const string NonSubscribers = "NonSubscribers";
}

/// <summary>Outcome of one monthly review batch run, printed by the worker and safe to log.</summary>
public sealed class MonthlyReviewSummaryDto
{
    public Guid RunId { get; set; }
    public int Year { get; set; }
    public int Month { get; set; }
    public string PlanCode { get; set; } = string.Empty;

    /// <summary>Subscribers or NonSubscribers - see <see cref="MonthlyReviewAudiences"/>.</summary>
    public string Audience { get; set; } = MonthlyReviewAudiences.Subscribers;

    public bool EmailsEnabled { get; set; }
    public int UsersConsidered { get; set; }
    public int ReportsGenerated { get; set; }
    public int EmailsSent { get; set; }
    public int Skipped { get; set; }
    public int Failures { get; set; }
    public List<MonthlyReviewFailureDto> FailureDetails { get; set; } = new();
    public DateTime StartedAtUtc { get; set; }
    public DateTime CompletedAtUtc { get; set; }
}

/// <summary>A single user the batch could not process, for fast triage from the worker output.</summary>
public sealed class MonthlyReviewFailureDto
{
    public Guid UserId { get; set; }
    public string? Email { get; set; }
    public string Message { get; set; } = string.Empty;
}
