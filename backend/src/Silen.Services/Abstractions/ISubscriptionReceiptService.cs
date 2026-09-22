using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

public interface ISubscriptionReceiptService
{
    /// <summary>Verifies a freshly completed native purchase against the matching store's
    /// server API and, if active, grants the plan resolved from the verified product id -
    /// never from a client-supplied plan choice.</summary>
    Task<UserSubscriptionModel> VerifyAndActivateAsync(
        Guid userId, VerifyPurchaseRequest request, CancellationToken cancellationToken = default);

    /// <summary>Re-verifies an already-known transaction (driven by a store webhook or the
    /// periodic reconciliation job) and updates entitlement to match its current state.
    /// A no-op when the transaction isn't already on file.</summary>
    Task ApplyStoreNotificationAsync(string store, string transactionId, CancellationToken cancellationToken = default);
}
