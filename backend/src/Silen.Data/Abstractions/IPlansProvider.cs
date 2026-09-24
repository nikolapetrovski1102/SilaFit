using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IPlansProvider
{
    Task<(List<SubscriptionPlanModel> Plans, List<PlanFeatureModel> Features)> GetAllAsync(CancellationToken cancellationToken = default);

    Task<UserSubscriptionModel?> PurchaseAsync(
        Guid userId, Guid planId, string billingCycle, CancellationToken cancellationToken = default);

    Task<UserSubscriptionModel?> GetActiveAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Every currently entitled subscriber of a plan (by code), with contact details -
    /// used by the monthly review batch to reach all paying users of a tier.</summary>
    Task<List<PlanSubscriberModel>> GetActiveSubscribersByPlanCodeAsync(
        string planCode, CancellationToken cancellationToken = default);

    /// <summary>The complement: active users with an email who are not currently entitled to a
    /// paid plan - the monthly review teaser audience.</summary>
    Task<List<PlanSubscriberModel>> GetNonSubscribersAsync(CancellationToken cancellationToken = default);

    /// <summary>Null when the caller has no active subscription (Free tier) or their plan
    /// has no entitlements row yet.</summary>
    Task<PlanEntitlementsModel?> GetEntitlementsForUserAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Upserts a verified store receipt, keyed on (Store, TransactionId) so the
    /// verify endpoint, webhooks, and the reconciliation job can all call this safely.</summary>
    Task<SubscriptionReceiptModel?> InsertReceiptAsync(
        Guid userId, Guid planId, string store, string productId, string transactionId,
        string? originalTransactionId, string? purchaseToken, string? rawPayload,
        string status, DateTime? expiresAtUtc, bool autoRenewing, CancellationToken cancellationToken = default);

    /// <summary>Grants entitlement from a server-verified receipt. planId must already have
    /// been resolved from the store's verified productId, never a client-claimed plan.</summary>
    Task<UserSubscriptionModel?> ActivateFromReceiptAsync(
        Guid userId, Guid planId, string billingCycle, DateTime expiresAtUtc,
        Guid receiptId, bool autoRenewing, CancellationToken cancellationToken = default);

    /// <summary>Active, auto-renewing receipts due for a store re-check, oldest-verified first -
    /// the batch the periodic reconciliation job walks.</summary>
    Task<List<SubscriptionReceiptModel>> GetReceiptsForReconciliationAsync(
        int batchSize = 200, CancellationToken cancellationToken = default);

    /// <summary>Looks up a receipt by its store natural key - how a webhook/reconciliation
    /// event identifies a transaction before re-verifying and re-activating it.</summary>
    Task<SubscriptionReceiptModel?> GetReceiptByStoreTransactionAsync(
        string store, string transactionId, CancellationToken cancellationToken = default);

    /// <summary>Looks up a PlayStore receipt by its purchase token - how a Google Pub/Sub
    /// notification (which only carries the token, not the order id TransactionId is keyed
    /// on) resolves which transaction to re-verify.</summary>
    Task<SubscriptionReceiptModel?> GetReceiptByPurchaseTokenAsync(
        string purchaseToken, CancellationToken cancellationToken = default);

    /// <summary>Finds the receipt that first tied a store subscription to a Silen account -
    /// matched by App Store original transaction id or Play purchase token, both of which stay
    /// the same across renewals. Null when no account has claimed it yet.</summary>
    Task<SubscriptionReceiptModel?> GetSubscriptionOwnerAsync(
        string store, string? originalTransactionId, string? purchaseToken, CancellationToken cancellationToken = default);

    /// <summary>Moves a subscription out of Active (Cancelled/Expired) without granting
    /// entitlement - used when a store check finds the receipt is no longer current.</summary>
    Task UpdateSubscriptionStatusAsync(Guid userId, string status, CancellationToken cancellationToken = default);
}
