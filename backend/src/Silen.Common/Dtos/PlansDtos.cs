using Silen.Common.Models;

namespace Silen.Common.Dtos;

public sealed class PlanCatalogEntryDto
{
    public SubscriptionPlanModel Plan { get; set; } = new();
    public List<PlanFeatureModel> Features { get; set; } = new();
}

public sealed class PurchaseRequest
{
    public Guid PlanId { get; set; }

    /// <summary>"Monthly" or "Yearly".</summary>
    public string BillingCycle { get; set; } = "Monthly";
}
