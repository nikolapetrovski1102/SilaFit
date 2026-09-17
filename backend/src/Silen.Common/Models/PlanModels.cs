namespace Silen.Common.Models;

public sealed class SubscriptionPlanModel
{
    public Guid PlanId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Tagline { get; set; }
    public decimal MonthlyPrice { get; set; }
    public decimal YearlyPrice { get; set; }
    public bool IsFeatured { get; set; }
    public int SortOrder { get; set; }
}

public sealed class PlanFeatureModel
{
    public Guid PlanId { get; set; }
    public string FeatureText { get; set; } = string.Empty;
    public byte SortOrder { get; set; }
    public bool IsHighlighted { get; set; }
}

public sealed class UserSubscriptionModel
{
    public Guid UserId { get; set; }
    public Guid PlanId { get; set; }
    public string BillingCycle { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public DateTime StartedAtUtc { get; set; }
    public DateTime? ExpiresAtUtc { get; set; }
    public string? PlanCode { get; set; }
    public string? PlanName { get; set; }
}

/// <summary>What a plan actually entitles its subscriber to. Null on a limit means
/// unlimited. A Free/unsubscribed caller has no row to read here - see
/// ISubscriptionGate.GetEntitlementsAsync for the hardcoded fallback.</summary>
public sealed class PlanEntitlementsModel
{
    public int? MaxActiveSplits { get; set; }
    public int? MaxActiveDietPlans { get; set; }
    public bool AllowAiGeneration { get; set; }
}
