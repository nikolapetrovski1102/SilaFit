namespace Silen.Common.Models;

/// <summary>A decoded, server-verified App Store Server API transaction. The JWS payload is
/// read directly (issuer/bundle-id/expiry checked) without walking Apple's x5c certificate
/// chain - a pragmatic middle ground, since the request that fetched it was itself
/// authenticated to Apple over TLS via our own signed JWT.</summary>
public sealed class AppStoreTransactionInfo
{
    public string TransactionId { get; set; } = string.Empty;
    public string OriginalTransactionId { get; set; } = string.Empty;
    public string ProductId { get; set; } = string.Empty;
    public string BundleId { get; set; } = string.Empty;
    public DateTime PurchaseAtUtc { get; set; }
    public DateTime? ExpiresAtUtc { get; set; }
    public DateTime? RevokedAtUtc { get; set; }
    public string RawPayloadJson { get; set; } = string.Empty;
}

/// <summary>A subscriptionsv2.get response from the Play Developer API.</summary>
public sealed class GooglePlaySubscriptionInfo
{
    public string ProductId { get; set; } = string.Empty;

    /// <summary>Google's order id for the current billing period - the closest analog to Apple's transactionId.</summary>
    public string? LatestOrderId { get; set; }

    public DateTime? ExpiresAtUtc { get; set; }
    public bool AutoRenewing { get; set; }

    /// <summary>One of Google's SUBSCRIPTION_STATE_* values (ACTIVE, CANCELED, EXPIRED, IN_GRACE_PERIOD, ON_HOLD, PAUSED, PENDING).</summary>
    public string SubscriptionState { get; set; } = string.Empty;

    public bool Acknowledged { get; set; }
    public string RawPayloadJson { get; set; } = string.Empty;
}
