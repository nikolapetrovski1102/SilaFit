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
