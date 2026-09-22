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
}
