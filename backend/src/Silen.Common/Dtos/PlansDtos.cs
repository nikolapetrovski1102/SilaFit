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

/// <summary>Sent after a successful native purchase. The plan granted is derived server-side
/// from the store-verified ProductId, never from a client-supplied plan id.</summary>
public sealed class VerifyPurchaseRequest
{
    /// <summary>"AppStore" or "PlayStore".</summary>
    public string Store { get; set; } = string.Empty;

    /// <summary>The store product id the client purchased (must match a SubscriptionPlans row).</summary>
    public string ProductId { get; set; } = string.Empty;

    /// <summary>Android: the Play Billing purchase token. iOS: raw audit data (verification
    /// itself uses TransactionId against Apple's App Store Server API).</summary>
    public string ReceiptData { get; set; } = string.Empty;

    /// <summary>Required for AppStore purchases - StoreKit's transaction/purchase id.</summary>
    public string? TransactionId { get; set; }
}

public sealed class RedeemPromoCodeRequest
{
    public string Code { get; set; } = string.Empty;
}

/// <summary>An accepted Silen discount code: the Play subscription offer it unlocks on the
/// paywall, and until when the code itself can still be entered.</summary>
public sealed class PromoCodeDto
{
    public string Code { get; set; } = string.Empty;
    public string PlayOfferId { get; set; } = string.Empty;
    public DateTime? ExpiresAtUtc { get; set; }
}
