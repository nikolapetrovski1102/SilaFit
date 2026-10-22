using Silen.Common.Models;

namespace Silen.Services.Abstractions;

public interface IAppStoreServerClient
{
    /// <summary>Whether AppStoreServer credentials (key id, issuer id, private key) are configured.</summary>
    bool IsConfigured { get; }

    /// <summary>Fetches and decodes a transaction from Apple's App Store Server API
    /// (GET /inApps/v1/transactions/{id}). Returns null when unconfigured, the
    /// transaction doesn't exist, or its bundle id doesn't match ours.</summary>
    Task<AppStoreTransactionInfo?> GetTransactionInfoAsync(string transactionId, CancellationToken cancellationToken = default);

    /// <summary>Fetches the current state of the subscription any of its transactions belongs
    /// to (GET /inApps/v1/subscriptions/{id}): its latest transaction and auto-renew status.
    /// <paramref name="originalTransactionId"/> picks the right subscription when the account
    /// has several. Returns null when unconfigured or Apple can't be reached.</summary>
    Task<AppStoreSubscriptionStatus?> GetSubscriptionStatusAsync(
        string transactionId, string? originalTransactionId, CancellationToken cancellationToken = default);
}
