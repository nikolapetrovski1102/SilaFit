using Microsoft.Extensions.Logging;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="ISubscriptionReceiptService"/>
public sealed class SubscriptionReceiptService(
    IPlansProvider plansProvider,
    IAppStoreServerClient appStoreServerClient,
    IGooglePlayDeveloperClient googlePlayDeveloperClient,
    ILogger<SubscriptionReceiptService> logger) : ISubscriptionReceiptService
{
    public async Task<UserSubscriptionModel> VerifyAndActivateAsync(
        Guid userId, VerifyPurchaseRequest request, CancellationToken cancellationToken = default)
    {
        if (request.Store is not ("AppStore" or "PlayStore"))
        {
            throw new ValidationException($"Unsupported store '{request.Store}'.", "We couldn't verify that purchase.");
        }

        if (string.IsNullOrWhiteSpace(request.ProductId))
        {
            throw new ValidationException("ProductId is required.");
        }

        var (plans, _) = await plansProvider.GetAllAsync(cancellationToken);
        var resolved = ResolvePlan(plans, request.Store, request.ProductId)
            ?? throw new ValidationException($"Unknown product id '{request.ProductId}'.", "That purchase doesn't match a known plan.");

        string transactionId;
        string? originalTransactionId;
        string? purchaseToken = null;
        string status;
        DateTime? expiresAtUtc;
        bool autoRenewing;
        string rawPayload;

        if (request.Store == "AppStore")
        {
            if (string.IsNullOrWhiteSpace(request.TransactionId))
            {
                throw new ValidationException("TransactionId is required for AppStore purchases.");
            }

            var info = await appStoreServerClient.GetTransactionInfoAsync(request.TransactionId, cancellationToken)
                ?? throw new ValidationException(
                    $"Could not verify App Store transaction '{request.TransactionId}'.", "We couldn't verify that purchase with Apple.");

            if (!string.Equals(info.ProductId, request.ProductId, StringComparison.Ordinal))
            {
                throw new ValidationException("Verified product id did not match the requested purchase.");
            }

            transactionId = info.TransactionId;
            originalTransactionId = info.OriginalTransactionId;
            expiresAtUtc = info.ExpiresAtUtc;
            status = info.RevokedAtUtc is not null ? "Refunded"
                : expiresAtUtc is not null && expiresAtUtc <= DateTime.UtcNow ? "Expired"
                : "Active";
            autoRenewing = status == "Active";
            rawPayload = info.RawPayloadJson;
        }
        else
        {
            if (string.IsNullOrWhiteSpace(request.ReceiptData))
            {
                throw new ValidationException("ReceiptData (purchase token) is required for PlayStore purchases.");
            }

            purchaseToken = request.ReceiptData;
            var info = await googlePlayDeveloperClient.GetSubscriptionAsync(purchaseToken, cancellationToken)
                ?? throw new ValidationException("Could not verify Play Store purchase token.", "We couldn't verify that purchase with Google Play.");

            if (!string.Equals(info.ProductId, request.ProductId, StringComparison.Ordinal))
            {
                throw new ValidationException("Verified product id did not match the requested purchase.");
            }

            transactionId = info.LatestOrderId ?? purchaseToken;
            originalTransactionId = null;
            expiresAtUtc = info.ExpiresAtUtc;
            autoRenewing = info.AutoRenewing;
            status = MapPlayStatus(info.SubscriptionState);
            rawPayload = info.RawPayloadJson;

            if (!info.Acknowledged)
            {
                // Best-effort - a failed acknowledge doesn't block entitlement; Google retries
                // are not something we can drive from here, so a late ack just risks Google's
                // own 3-day auto-refund window rather than this request failing.
                _ = await googlePlayDeveloperClient.AcknowledgeAsync(purchaseToken, request.ProductId, cancellationToken);
            }
        }

        var receipt = await plansProvider.InsertReceiptAsync(
            userId, resolved.PlanId, request.Store, request.ProductId, transactionId,
            originalTransactionId, purchaseToken, rawPayload, status, expiresAtUtc, autoRenewing, cancellationToken)
            ?? throw new NotFoundException($"Receipt upsert for transaction '{transactionId}' did not return a row.");

        if (status != "Active")
        {
            throw new ValidationException($"Verified purchase status was '{status}', not Active.", "That purchase isn't currently active.");
        }

        if (expiresAtUtc is null)
        {
            throw new ValidationException("Verified purchase had no expiry date.", "We couldn't verify that purchase.");
        }

        return await plansProvider.ActivateFromReceiptAsync(
            userId, resolved.PlanId, resolved.BillingCycle, expiresAtUtc.Value, receipt.ReceiptId, autoRenewing, cancellationToken)
            ?? throw new NotFoundException($"Activation for user '{userId}' did not return a subscription row.");
    }

    public async Task ApplyStoreNotificationAsync(string store, string transactionId, CancellationToken cancellationToken = default)
    {
        var existing = await plansProvider.GetReceiptByStoreTransactionAsync(store, transactionId, cancellationToken);
        if (existing is null)
        {
            // Most likely a race with the client-triggered verify call for a brand-new
            // purchase, which will create the row itself - nothing to reconcile yet.
            logger.LogInformation("Ignoring store notification for unknown {Store} transaction '{TransactionId}'.", store, transactionId);
            return;
        }

        string status;
        DateTime? expiresAtUtc;
        bool autoRenewing;
        string rawPayload;
        var originalTransactionId = existing.OriginalTransactionId;

        if (string.Equals(store, "AppStore", StringComparison.Ordinal))
        {
            var info = await appStoreServerClient.GetTransactionInfoAsync(transactionId, cancellationToken);
            if (info is null)
            {
                logger.LogWarning("Could not re-verify AppStore transaction '{TransactionId}' during reconciliation.", transactionId);
                return;
            }

            expiresAtUtc = info.ExpiresAtUtc;
            status = info.RevokedAtUtc is not null ? "Refunded"
                : expiresAtUtc is not null && expiresAtUtc <= DateTime.UtcNow ? "Expired"
                : "Active";
            autoRenewing = status == "Active";
            rawPayload = info.RawPayloadJson;
            originalTransactionId = info.OriginalTransactionId;
        }
        else if (string.Equals(store, "PlayStore", StringComparison.Ordinal))
        {
            if (string.IsNullOrWhiteSpace(existing.PurchaseToken))
            {
                logger.LogWarning("PlayStore receipt for transaction '{TransactionId}' has no purchase token to re-verify.", transactionId);
                return;
            }

            var info = await googlePlayDeveloperClient.GetSubscriptionAsync(existing.PurchaseToken, cancellationToken);
            if (info is null)
            {
                logger.LogWarning("Could not re-verify PlayStore purchase token for transaction '{TransactionId}' during reconciliation.", transactionId);
                return;
            }

            expiresAtUtc = info.ExpiresAtUtc;
            autoRenewing = info.AutoRenewing;
            status = MapPlayStatus(info.SubscriptionState);
            rawPayload = info.RawPayloadJson;
        }
        else
        {
            logger.LogWarning("Unsupported store '{Store}' in ApplyStoreNotificationAsync.", store);
            return;
        }

        await plansProvider.InsertReceiptAsync(
            existing.UserId, existing.PlanId, store, existing.ProductId, transactionId,
            originalTransactionId, existing.PurchaseToken, rawPayload, status, expiresAtUtc, autoRenewing, cancellationToken);

        if (status == "Active" && expiresAtUtc is not null)
        {
            var currentSubscription = await plansProvider.GetActiveAsync(existing.UserId, cancellationToken);
            var billingCycle = currentSubscription?.BillingCycle ?? "Monthly";
            await plansProvider.ActivateFromReceiptAsync(
                existing.UserId, existing.PlanId, billingCycle, expiresAtUtc.Value, existing.ReceiptId, autoRenewing, cancellationToken);
        }
        else
        {
            var subscriptionStatus = status == "Expired" ? "Expired" : "Cancelled";
            await plansProvider.UpdateSubscriptionStatusAsync(existing.UserId, subscriptionStatus, cancellationToken);
        }
    }

    private static (Guid PlanId, string BillingCycle)? ResolvePlan(List<SubscriptionPlanModel> plans, string store, string productId)
    {
        foreach (var plan in plans)
        {
            if (store == "AppStore")
            {
                if (string.Equals(plan.AppStoreMonthlyProductId, productId, StringComparison.Ordinal))
                {
                    return (plan.PlanId, "Monthly");
                }

                if (string.Equals(plan.AppStoreYearlyProductId, productId, StringComparison.Ordinal))
                {
                    return (plan.PlanId, "Yearly");
                }
            }
            else
            {
                if (string.Equals(plan.PlayStoreMonthlyProductId, productId, StringComparison.Ordinal))
                {
                    return (plan.PlanId, "Monthly");
                }

                if (string.Equals(plan.PlayStoreYearlyProductId, productId, StringComparison.Ordinal))
                {
                    return (plan.PlanId, "Yearly");
                }
            }
        }

        return null;
    }

    private static string MapPlayStatus(string subscriptionState) => subscriptionState switch
    {
        "SUBSCRIPTION_STATE_ACTIVE" or "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" => "Active",
        "SUBSCRIPTION_STATE_CANCELED" => "Cancelled",
        "SUBSCRIPTION_STATE_EXPIRED" => "Expired",
        _ => "Pending"
    };
}
