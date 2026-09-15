namespace Silen.Common.Models;

/// <summary>Which audience a monthly review delivery belongs to. Persisted in
/// dbo.MonthlyReviewDeliveries.DeliveryKind and used for per-audience idempotency.</summary>
public static class MonthlyReviewDeliveryKinds
{
    /// <summary>The full AI report, sent to active PRO/ADVANCED subscribers.</summary>
    public const string Subscriber = "Subscriber";

    /// <summary>The stats teaser + upgrade CTA, sent to non-paying users.</summary>
    public const string Upsell = "Upsell";
}

/// <summary>A paying subscriber of a given plan, with the contact details the monthly review batch needs.</summary>
public sealed class PlanSubscriberModel
{
    public Guid UserId { get; set; }
    public string? DisplayName { get; set; }
    public string? Email { get; set; }
    public string PlanCode { get; set; } = string.Empty;
    public DateTime? ExpiresAtUtc { get; set; }
}

/// <summary>One execution of the monthly review batch, as recorded in dbo.MonthlyReviewRuns.</summary>
public sealed class MonthlyReviewRunModel
{
    public Guid RunId { get; set; }
    public int PeriodYear { get; set; }
    public int PeriodMonth { get; set; }
    public string PlanCode { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public int UsersConsidered { get; set; }
    public int ReportsGenerated { get; set; }
    public int EmailsSent { get; set; }
    public int Failures { get; set; }
    public DateTime StartedAtUtc { get; set; }
    public DateTime? CompletedAtUtc { get; set; }
}

/// <summary>Per-user outcome recorded in dbo.MonthlyReviewDeliveries.</summary>
public sealed class MonthlyReviewDeliveryModel
{
    public Guid RunId { get; set; }
    public Guid UserId { get; set; }
    public int PeriodYear { get; set; }
    public int PeriodMonth { get; set; }
    public string Status { get; set; } = string.Empty;
    public string? ErrorMessage { get; set; }
    public DateTime? GeneratedAtUtc { get; set; }
    public DateTime? EmailedAtUtc { get; set; }

    /// <summary>Subscriber (full report) or Upsell (non-paying teaser) - see <see cref="MonthlyReviewDeliveryKinds"/>.</summary>
    public string DeliveryKind { get; set; } = MonthlyReviewDeliveryKinds.Subscriber;
}
