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
    public string? AppStoreMonthlyProductId { get; set; }
    public string? AppStoreYearlyProductId { get; set; }
    public string? PlayStoreMonthlyProductId { get; set; }
    public string? PlayStoreYearlyProductId { get; set; }
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
    public Guid? LatestReceiptId { get; set; }
    public bool AutoRenewing { get; set; }
}

/// <summary>An append-only, server-verified record of a single App Store /
/// Play Store transaction. Uniquely keyed on (Store, TransactionId) so the
/// verify endpoint, store webhooks, and the reconciliation job can all write
/// the same transaction without double-crediting it.</summary>
public sealed class SubscriptionReceiptModel
{
    public Guid ReceiptId { get; set; }
    public Guid UserId { get; set; }
    public Guid PlanId { get; set; }
    public string Store { get; set; } = string.Empty;
    public string ProductId { get; set; } = string.Empty;
    public string TransactionId { get; set; } = string.Empty;
    public string? OriginalTransactionId { get; set; }
    public string? PurchaseToken { get; set; }
    public string? RawPayload { get; set; }
    public string Status { get; set; } = string.Empty;
    public DateTime? ExpiresAtUtc { get; set; }
    public bool AutoRenewing { get; set; }
    public DateTime VerifiedAtUtc { get; set; }
    public DateTime CreatedAtUtc { get; set; }
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
