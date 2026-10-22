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

/// <summary>One subscription's entry in an App Store Server API "Get All Subscription
/// Statuses" response: the latest transaction (which moves forward on every renewal)
/// plus the renewal info that says whether the user has turned auto-renew off.</summary>
public sealed class AppStoreSubscriptionStatus
{
    /// <summary>Apple's status code: 1 active, 2 expired, 3 billing retry, 4 billing grace period, 5 revoked.</summary>
    public int Status { get; set; }

    public AppStoreTransactionInfo LatestTransaction { get; set; } = new();

    /// <summary>False once the user cancels - they keep access until the latest transaction expires.</summary>
    public bool AutoRenewing { get; set; }

    /// <summary>Set while Apple is retrying a failed renewal inside a billing grace period,
    /// during which the user stays entitled past the transaction's own expiry.</summary>
    public DateTime? GracePeriodExpiresAtUtc { get; set; }
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
