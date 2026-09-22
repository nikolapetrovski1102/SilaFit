using Silen.Common.Models;

namespace Silen.Services.Abstractions;

public interface IGooglePlayDeveloperClient
{
    /// <summary>Whether a Play Developer API service account is configured.</summary>
    bool IsConfigured { get; }

    /// <summary>Fetches current subscription state for a purchase token (purchases.subscriptionsv2.get).
    /// Returns null when unconfigured, the token is invalid, or the call fails.</summary>
    Task<GooglePlaySubscriptionInfo?> GetSubscriptionAsync(string purchaseToken, CancellationToken cancellationToken = default);

    /// <summary>Acknowledges a purchase - required by Google within 3 days of purchase or the
    /// subscription is automatically refunded. Safe to call again on an already-acknowledged purchase.</summary>
    Task<bool> AcknowledgeAsync(string purchaseToken, string productId, CancellationToken cancellationToken = default);
}
