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
            var subscriptionStatus = await appStoreServerClient.GetSubscriptionStatusAsync(
                info.TransactionId, info.OriginalTransactionId, cancellationToken);
            (status, expiresAtUtc, autoRenewing) = MapAppStoreState(info, subscriptionStatus);
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
            status = MapPlayStatus(info.SubscriptionState, expiresAtUtc);
            rawPayload = info.RawPayloadJson;

            if (!info.Acknowledged)
            {
                // Best-effort - a failed acknowledge doesn't block entitlement; Google retries
                // are not something we can drive from here, so a late ack just risks Google's
                // own 3-day auto-refund window rather than this request failing.
                _ = await googlePlayDeveloperClient.AcknowledgeAsync(purchaseToken, request.ProductId, cancellationToken);
            }
        }

        // One store subscription backs one Silen account. Without this, signing into a
        // second account and tapping Restore (or posting someone else's transaction id)
        // would unlock it there too, while renewals kept flowing only to the first.
        var owner = await plansProvider.GetSubscriptionOwnerAsync(
            request.Store, originalTransactionId, purchaseToken, cancellationToken);
        if (owner is not null && owner.UserId != userId)
        {
            throw new ConflictException(
                $"{request.Store} subscription is already linked to user '{owner.UserId}'.",
                "This subscription is linked to a different Silen account. Sign in with that account to use it.");
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

    public async Task ApplyStoreNotificationAsync(
        string store, string transactionId, string? originalTransactionId = null, CancellationToken cancellationToken = default)
    {
        var existing = await plansProvider.GetReceiptByStoreTransactionAsync(store, transactionId, cancellationToken);
        if (existing is null && !string.IsNullOrWhiteSpace(originalTransactionId))
        {
            // Apple notifies with the subscription's newest transaction, which is a renewal
            // we haven't seen whenever the app wasn't opened since it renewed - the original
            // transaction id (shared by every renewal) still finds the subscription's owner.
            existing = await plansProvider.GetSubscriptionOwnerAsync(store, originalTransactionId, null, cancellationToken);
        }

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
        var receiptTransactionId = existing.TransactionId;
        var productId = existing.ProductId;
        var resolvedOriginalTransactionId = existing.OriginalTransactionId;

        if (string.Equals(store, "AppStore", StringComparison.Ordinal))
        {
            // The subscription status carries the latest transaction (so renewals move the
            // expiry forward) and the renewal info (so a cancellation is recorded).
            var subscriptionStatus = await appStoreServerClient.GetSubscriptionStatusAsync(
                transactionId, existing.OriginalTransactionId, cancellationToken);
            var info = subscriptionStatus?.LatestTransaction
                ?? await appStoreServerClient.GetTransactionInfoAsync(transactionId, cancellationToken);
            if (info is null)
            {
                logger.LogWarning("Could not re-verify AppStore transaction '{TransactionId}' during reconciliation.", transactionId);
                return;
            }

            (status, expiresAtUtc, autoRenewing) = MapAppStoreState(info, subscriptionStatus);
            rawPayload = info.RawPayloadJson;
            receiptTransactionId = info.TransactionId;
            productId = string.IsNullOrWhiteSpace(info.ProductId) ? existing.ProductId : info.ProductId;
            resolvedOriginalTransactionId = info.OriginalTransactionId;
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
            status = MapPlayStatus(info.SubscriptionState, expiresAtUtc);
            rawPayload = info.RawPayloadJson;
        }
        else
        {
            logger.LogWarning("Unsupported store '{Store}' in ApplyStoreNotificationAsync.", store);
            return;
        }

        // A renewal into a different product (an upgrade/downgrade within the group)
        // moves the user onto that product's plan.
        var planId = existing.PlanId;
        string? billingCycle = null;
        if (!string.Equals(productId, existing.ProductId, StringComparison.Ordinal))
        {
            var (plans, _) = await plansProvider.GetAllAsync(cancellationToken);
            if (ResolvePlan(plans, store, productId) is { } resolved)
            {
                planId = resolved.PlanId;
                billingCycle = resolved.BillingCycle;
            }
            else
            {
                productId = existing.ProductId;
            }
        }

        var receipt = await plansProvider.InsertReceiptAsync(
            existing.UserId, planId, store, productId, receiptTransactionId,
            resolvedOriginalTransactionId, existing.PurchaseToken, rawPayload, status, expiresAtUtc, autoRenewing, cancellationToken);

        var currentSubscription = await plansProvider.GetActiveAsync(existing.UserId, cancellationToken);
        if (!await BacksCurrentPlanAsync(existing, receipt?.ReceiptId, status, currentSubscription, cancellationToken))
        {
            logger.LogInformation(
                "{Store} transaction '{TransactionId}' is {Status} but no longer backs user '{UserId}''s plan - receipt updated only.",
                store, transactionId, status, existing.UserId);
            return;
        }

        if (status == "Active" && expiresAtUtc is not null)
        {
            billingCycle ??= currentSubscription?.BillingCycle ?? "Monthly";

            await plansProvider.ActivateFromReceiptAsync(
                existing.UserId, planId, billingCycle, expiresAtUtc.Value, receipt?.ReceiptId ?? existing.ReceiptId, autoRenewing, cancellationToken);
        }
        else
        {
            var subscriptionStatus = status == "Expired" ? "Expired" : "Cancelled";
            await plansProvider.UpdateSubscriptionStatusAsync(existing.UserId, subscriptionStatus, cancellationToken);
        }
    }

    /// <summary>Whether a re-checked store subscription may change the user's plan. The user
    /// has one plan row but can hold several store subscriptions over time - a Play
    /// upgrade replaces the purchase token, a duplicate purchase leaves two running - and
    /// the replaced one keeps producing notifications. Only the subscription behind the
    /// current plan may move it; another one may take over only a plan that has lapsed.</summary>
    private async Task<bool> BacksCurrentPlanAsync(
        SubscriptionReceiptModel existing, Guid? upsertedReceiptId, string status,
        UserSubscriptionModel? current, CancellationToken cancellationToken)
    {
        // A live partner grant is ended only by the partner's cancel call, never by a
        // notification for some older store subscription.
        if (current is { IsPartnerGrant: true }
            && string.Equals(current.Status, "Active", StringComparison.OrdinalIgnoreCase)
            && (current.ExpiresAtUtc is null || current.ExpiresAtUtc > DateTime.UtcNow))
        {
            return false;
        }

        if (current?.LatestReceiptId is not { } latestReceiptId
            || latestReceiptId == existing.ReceiptId
            || latestReceiptId == upsertedReceiptId)
        {
            return true;
        }

        var latest = await plansProvider.GetReceiptByIdAsync(latestReceiptId, cancellationToken);
        if (latest is null || IsSameStoreSubscription(latest, existing))
        {
            return true;
        }

        var currentIsLive = string.Equals(current.Status, "Active", StringComparison.OrdinalIgnoreCase)
            && (current.ExpiresAtUtc is null || current.ExpiresAtUtc > DateTime.UtcNow);
        return status == "Active" && !currentIsLive;
    }

    // Play's purchase token and the App Store's original transaction id both stay the
    // same across renewals, so either identifies one store subscription.
    private static bool IsSameStoreSubscription(SubscriptionReceiptModel a, SubscriptionReceiptModel b) =>
        string.Equals(a.Store, b.Store, StringComparison.Ordinal)
        && (a.Store == "PlayStore"
            ? !string.IsNullOrEmpty(a.PurchaseToken) && string.Equals(a.PurchaseToken, b.PurchaseToken, StringComparison.Ordinal)
            : !string.IsNullOrEmpty(a.OriginalTransactionId)
              && string.Equals(a.OriginalTransactionId, b.OriginalTransactionId, StringComparison.Ordinal));

    /// <summary>Entitlement for an App Store transaction. A cancelled subscription stays
    /// Active (with auto-renew off) until it expires - the user paid for that period.
    /// The subscription status, when available, supplies auto-renew and any billing
    /// grace period; it only describes <paramref name="transaction"/> if that is the
    /// subscription's latest transaction.</summary>
    private static (string Status, DateTime? ExpiresAtUtc, bool AutoRenewing) MapAppStoreState(
        AppStoreTransactionInfo transaction, AppStoreSubscriptionStatus? subscriptionStatus)
    {
        var isLatest = subscriptionStatus is not null
            && string.Equals(subscriptionStatus.LatestTransaction.TransactionId, transaction.TransactionId, StringComparison.Ordinal);

        var expiresAtUtc = transaction.ExpiresAtUtc;
        if (isLatest && subscriptionStatus!.Status == 4
            && subscriptionStatus.GracePeriodExpiresAtUtc is { } graceEnd
            && (expiresAtUtc is null || graceEnd > expiresAtUtc))
        {
            expiresAtUtc = graceEnd;
        }

        var status = transaction.RevokedAtUtc is not null || (isLatest && subscriptionStatus!.Status == 5) ? "Refunded"
            : expiresAtUtc is not null && expiresAtUtc <= DateTime.UtcNow ? "Expired"
            : "Active";

        // Without a status response, assume a live transaction renews - the next webhook
        // or reconciliation pass corrects it.
        var autoRenewing = status == "Active" && (subscriptionStatus?.AutoRenewing ?? true);
        return (status, expiresAtUtc, autoRenewing);
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

    // Play's CANCELED means auto-renew is off, not that access has ended - the user keeps
    // the plan until the period they paid for runs out (autoRenewEnabled is already false).
    private static string MapPlayStatus(string subscriptionState, DateTime? expiresAtUtc) => subscriptionState switch
    {
        "SUBSCRIPTION_STATE_ACTIVE" or "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" => "Active",
        "SUBSCRIPTION_STATE_CANCELED" => expiresAtUtc is not null && expiresAtUtc > DateTime.UtcNow ? "Active" : "Expired",
        "SUBSCRIPTION_STATE_EXPIRED" => "Expired",
        _ => "Pending"
    };
}
