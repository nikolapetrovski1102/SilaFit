using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class SubscriptionReceiptServiceTests
{
    private const string MonthlyProductId = "silen.pro.monthly";
    private const string OriginalTransactionId = "2000000100000001";
    private const string TransactionId = "2000000100000042";
    private const string PurchaseToken = "play-purchase-token";

    private readonly Mock<IPlansProvider> plansProvider = new(MockBehavior.Strict);
    private readonly Mock<IAppStoreServerClient> appStoreClient = new(MockBehavior.Strict);
    private readonly Mock<IGooglePlayDeveloperClient> googlePlayClient = new(MockBehavior.Strict);
    private readonly Guid planId = Guid.NewGuid();

    private SubscriptionReceiptService Sut() => new(
        plansProvider.Object, appStoreClient.Object, googlePlayClient.Object,
        NullLogger<SubscriptionReceiptService>.Instance);

    private void SetupCatalog() =>
        plansProvider.Setup(p => p.GetAllAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(([
                new SubscriptionPlanModel
                {
                    PlanId = planId,
                    Code = "PRO",
                    AppStoreMonthlyProductId = MonthlyProductId,
                    PlayStoreMonthlyProductId = MonthlyProductId
                }
            ], []));

    private static AppStoreTransactionInfo AppStoreTransaction(string transactionId = TransactionId, DateTime? expiresAtUtc = null) => new()
    {
        TransactionId = transactionId,
        OriginalTransactionId = OriginalTransactionId,
        ProductId = MonthlyProductId,
        ExpiresAtUtc = expiresAtUtc ?? DateTime.UtcNow.AddDays(20),
        RawPayloadJson = "{}"
    };

    private void SetupAppStoreTransaction(bool autoRenewing = true)
    {
        appStoreClient.Setup(c => c.GetTransactionInfoAsync(TransactionId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(AppStoreTransaction());
        SetupAppStoreStatus(TransactionId, AppStoreTransaction(), autoRenewing);
    }

    private void SetupAppStoreStatus(string transactionId, AppStoreTransactionInfo latest, bool autoRenewing) =>
        appStoreClient.Setup(c => c.GetSubscriptionStatusAsync(transactionId, OriginalTransactionId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AppStoreSubscriptionStatus
            {
                Status = latest.ExpiresAtUtc > DateTime.UtcNow ? 1 : 2,
                LatestTransaction = latest,
                AutoRenewing = autoRenewing
            });

    private void SetupOwner(string store, string? originalTransactionId, string? purchaseToken, Guid? ownerUserId) =>
        plansProvider.Setup(p => p.GetSubscriptionOwnerAsync(store, originalTransactionId, purchaseToken, It.IsAny<CancellationToken>()))
            .ReturnsAsync(ownerUserId is null ? null : new SubscriptionReceiptModel { UserId = ownerUserId.Value });

    private void SetupActivation(Guid userId)
    {
        var receiptId = Guid.NewGuid();
        plansProvider.Setup(p => p.InsertReceiptAsync(
                userId, planId, It.IsAny<string>(), MonthlyProductId, It.IsAny<string>(), It.IsAny<string?>(),
                It.IsAny<string?>(), It.IsAny<string?>(), "Active", It.IsAny<DateTime?>(), It.IsAny<bool>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(new SubscriptionReceiptModel { ReceiptId = receiptId, UserId = userId });
        plansProvider.Setup(p => p.ActivateFromReceiptAsync(
                userId, planId, "Monthly", It.IsAny<DateTime>(), receiptId, It.IsAny<bool>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new UserSubscriptionModel { UserId = userId, PlanId = planId, Status = "Active" });
    }

    private static VerifyPurchaseRequest AppStoreRequest() => new()
    {
        Store = "AppStore",
        ProductId = MonthlyProductId,
        TransactionId = TransactionId
    };

    [Fact]
    public async Task VerifyAndActivateAsync_AppStoreSubscriptionOwnedByAnotherUser_ThrowsConflictWithoutActivating()
    {
        var userId = Guid.NewGuid();
        SetupCatalog();
        SetupAppStoreTransaction();
        SetupOwner("AppStore", OriginalTransactionId, null, ownerUserId: Guid.NewGuid());

        var ex = await Assert.ThrowsAsync<ConflictException>(() => Sut().VerifyAndActivateAsync(userId, AppStoreRequest()));

        Assert.Equal(409, ex.StatusCode);
        plansProvider.Verify(p => p.ActivateFromReceiptAsync(
            It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<string>(), It.IsAny<DateTime>(), It.IsAny<Guid>(),
            It.IsAny<bool>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task VerifyAndActivateAsync_AppStoreRestoreBySameOwner_Activates()
    {
        var userId = Guid.NewGuid();
        SetupCatalog();
        SetupAppStoreTransaction();
        SetupOwner("AppStore", OriginalTransactionId, null, ownerUserId: userId);
        SetupActivation(userId);

        var result = await Sut().VerifyAndActivateAsync(userId, AppStoreRequest());

        Assert.Equal("Active", result.Status);
    }

    [Fact]
    public async Task VerifyAndActivateAsync_UnclaimedAppStoreSubscription_Activates()
    {
        var userId = Guid.NewGuid();
        SetupCatalog();
        SetupAppStoreTransaction();
        SetupOwner("AppStore", OriginalTransactionId, null, ownerUserId: null);
        SetupActivation(userId);

        var result = await Sut().VerifyAndActivateAsync(userId, AppStoreRequest());

        Assert.Equal(userId, result.UserId);
    }

    [Fact]
    public async Task VerifyAndActivateAsync_PlayStoreTokenOwnedByAnotherUser_ThrowsConflict()
    {
        SetupCatalog();
        googlePlayClient.Setup(c => c.GetSubscriptionAsync(PurchaseToken, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new GooglePlaySubscriptionInfo
            {
                ProductId = MonthlyProductId,
                LatestOrderId = "GPA.1234-5678-9012-34567",
                ExpiresAtUtc = DateTime.UtcNow.AddDays(20),
                SubscriptionState = "SUBSCRIPTION_STATE_ACTIVE",
                Acknowledged = true,
                RawPayloadJson = "{}"
            });
        SetupOwner("PlayStore", null, PurchaseToken, ownerUserId: Guid.NewGuid());

        await Assert.ThrowsAsync<ConflictException>(() => Sut().VerifyAndActivateAsync(Guid.NewGuid(), new VerifyPurchaseRequest
        {
            Store = "PlayStore",
            ProductId = MonthlyProductId,
            ReceiptData = PurchaseToken
        }));
    }

    [Fact]
    public async Task VerifyAndActivateAsync_CancelledAppStoreSubscription_StaysActiveWithoutAutoRenew()
    {
        var userId = Guid.NewGuid();
        SetupCatalog();
        SetupAppStoreTransaction(autoRenewing: false);
        SetupOwner("AppStore", OriginalTransactionId, null, ownerUserId: userId);
        SetupActivation(userId);

        await Sut().VerifyAndActivateAsync(userId, AppStoreRequest());

        plansProvider.Verify(p => p.ActivateFromReceiptAsync(
            userId, planId, "Monthly", It.IsAny<DateTime>(), It.IsAny<Guid>(), false, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task VerifyAndActivateAsync_CancelledPlayStoreSubscriptionInPaidPeriod_Activates()
    {
        var userId = Guid.NewGuid();
        SetupCatalog();
        googlePlayClient.Setup(c => c.GetSubscriptionAsync(PurchaseToken, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new GooglePlaySubscriptionInfo
            {
                ProductId = MonthlyProductId,
                LatestOrderId = "GPA.1234-5678-9012-34567",
                ExpiresAtUtc = DateTime.UtcNow.AddDays(5),
                AutoRenewing = false,
                SubscriptionState = "SUBSCRIPTION_STATE_CANCELED",
                Acknowledged = true,
                RawPayloadJson = "{}"
            });
        SetupOwner("PlayStore", null, PurchaseToken, ownerUserId: userId);
        SetupActivation(userId);

        var result = await Sut().VerifyAndActivateAsync(userId, new VerifyPurchaseRequest
        {
            Store = "PlayStore",
            ProductId = MonthlyProductId,
            ReceiptData = PurchaseToken
        });

        Assert.Equal("Active", result.Status);
        plansProvider.Verify(p => p.ActivateFromReceiptAsync(
            userId, planId, "Monthly", It.IsAny<DateTime>(), It.IsAny<Guid>(), false, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ApplyStoreNotificationAsync_AppStoreCancelled_RecordsAutoRenewOffAndKeepsAccess()
    {
        var userId = Guid.NewGuid();
        var existingReceiptId = Guid.NewGuid();
        plansProvider.Setup(p => p.GetReceiptByStoreTransactionAsync("AppStore", TransactionId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new SubscriptionReceiptModel
            {
                ReceiptId = existingReceiptId, UserId = userId, PlanId = planId, Store = "AppStore",
                ProductId = MonthlyProductId, TransactionId = TransactionId, OriginalTransactionId = OriginalTransactionId
            });
        SetupAppStoreStatus(TransactionId, AppStoreTransaction(), autoRenewing: false);
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new UserSubscriptionModel { UserId = userId, BillingCycle = "Monthly" });
        SetupActivation(userId);

        await Sut().ApplyStoreNotificationAsync("AppStore", TransactionId, OriginalTransactionId);

        plansProvider.Verify(p => p.InsertReceiptAsync(
            userId, planId, "AppStore", MonthlyProductId, TransactionId, OriginalTransactionId, null, "{}",
            "Active", It.IsAny<DateTime?>(), false, It.IsAny<CancellationToken>()), Times.Once);
        plansProvider.Verify(p => p.ActivateFromReceiptAsync(
            userId, planId, "Monthly", It.IsAny<DateTime>(), It.IsAny<Guid>(), false, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ApplyStoreNotificationAsync_AppStoreUnseenRenewalExpired_FindsOwnerAndExpires()
    {
        const string renewalTransactionId = "2000000100000099";
        var userId = Guid.NewGuid();
        plansProvider.Setup(p => p.GetReceiptByStoreTransactionAsync("AppStore", renewalTransactionId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((SubscriptionReceiptModel?)null);
        plansProvider.Setup(p => p.GetSubscriptionOwnerAsync("AppStore", OriginalTransactionId, null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new SubscriptionReceiptModel
            {
                ReceiptId = Guid.NewGuid(), UserId = userId, PlanId = planId, Store = "AppStore",
                ProductId = MonthlyProductId, TransactionId = TransactionId, OriginalTransactionId = OriginalTransactionId
            });
        SetupAppStoreStatus(renewalTransactionId,
            AppStoreTransaction(renewalTransactionId, DateTime.UtcNow.AddMinutes(-1)), autoRenewing: false);
        plansProvider.Setup(p => p.InsertReceiptAsync(
                userId, planId, "AppStore", MonthlyProductId, renewalTransactionId, OriginalTransactionId, null, "{}",
                "Expired", It.IsAny<DateTime?>(), false, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new SubscriptionReceiptModel { ReceiptId = Guid.NewGuid(), UserId = userId });
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new UserSubscriptionModel { UserId = userId, Status = "Active" });
        plansProvider.Setup(p => p.UpdateSubscriptionStatusAsync(userId, "Expired", It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        await Sut().ApplyStoreNotificationAsync("AppStore", renewalTransactionId, OriginalTransactionId);

        plansProvider.Verify(p => p.UpdateSubscriptionStatusAsync(userId, "Expired", It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ApplyStoreNotificationAsync_ExpiredStoreSubscription_LeavesLivePartnerGrantAlone()
    {
        // The user once bought in the App Store, then the partner website granted PRO. The
        // old store subscription expiring must not end the partner grant.
        const string renewalTransactionId = "2000000100000099";
        var userId = Guid.NewGuid();
        plansProvider.Setup(p => p.GetReceiptByStoreTransactionAsync("AppStore", renewalTransactionId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((SubscriptionReceiptModel?)null);
        plansProvider.Setup(p => p.GetSubscriptionOwnerAsync("AppStore", OriginalTransactionId, null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new SubscriptionReceiptModel
            {
                ReceiptId = Guid.NewGuid(), UserId = userId, PlanId = planId, Store = "AppStore",
                ProductId = MonthlyProductId, TransactionId = TransactionId, OriginalTransactionId = OriginalTransactionId
            });
        SetupAppStoreStatus(renewalTransactionId,
            AppStoreTransaction(renewalTransactionId, DateTime.UtcNow.AddMinutes(-1)), autoRenewing: false);
        plansProvider.Setup(p => p.InsertReceiptAsync(
                userId, planId, "AppStore", MonthlyProductId, renewalTransactionId, OriginalTransactionId, null, "{}",
                "Expired", It.IsAny<DateTime?>(), false, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new SubscriptionReceiptModel { ReceiptId = Guid.NewGuid(), UserId = userId });
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new UserSubscriptionModel { UserId = userId, Status = "Active", IsPartnerGrant = true });

        await Sut().ApplyStoreNotificationAsync("AppStore", renewalTransactionId, OriginalTransactionId);

        plansProvider.Verify(p => p.UpdateSubscriptionStatusAsync(It.IsAny<Guid>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task ApplyStoreNotificationAsync_PlayReplacedTokenExpired_LeavesNewerPlanAlone()
    {
        const string replacedToken = "play-replaced-token";
        var userId = Guid.NewGuid();
        var replacedReceiptId = Guid.NewGuid();
        var currentReceiptId = Guid.NewGuid();
        plansProvider.Setup(p => p.GetReceiptByStoreTransactionAsync("PlayStore", "GPA.old", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new SubscriptionReceiptModel
            {
                ReceiptId = replacedReceiptId, UserId = userId, PlanId = planId, Store = "PlayStore",
                ProductId = MonthlyProductId, TransactionId = "GPA.old", PurchaseToken = replacedToken
            });
        googlePlayClient.Setup(c => c.GetSubscriptionAsync(replacedToken, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new GooglePlaySubscriptionInfo
            {
                ProductId = MonthlyProductId, SubscriptionState = "SUBSCRIPTION_STATE_EXPIRED",
                ExpiresAtUtc = DateTime.UtcNow.AddMinutes(-1), RawPayloadJson = "{}"
            });
        plansProvider.Setup(p => p.InsertReceiptAsync(
                userId, planId, "PlayStore", MonthlyProductId, "GPA.old", null, replacedToken, "{}",
                "Expired", It.IsAny<DateTime?>(), false, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new SubscriptionReceiptModel { ReceiptId = replacedReceiptId, UserId = userId });
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new UserSubscriptionModel
            {
                UserId = userId, Status = "Active", PlanCode = "ADVANCED",
                ExpiresAtUtc = DateTime.UtcNow.AddDays(30), LatestReceiptId = currentReceiptId
            });
        plansProvider.Setup(p => p.GetReceiptByIdAsync(currentReceiptId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new SubscriptionReceiptModel
            {
                ReceiptId = currentReceiptId, UserId = userId, Store = "PlayStore", PurchaseToken = PurchaseToken
            });

        await Sut().ApplyStoreNotificationAsync("PlayStore", "GPA.old");

        plansProvider.Verify(p => p.UpdateSubscriptionStatusAsync(It.IsAny<Guid>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Never);
        plansProvider.Verify(p => p.ActivateFromReceiptAsync(
            It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<string>(), It.IsAny<DateTime>(), It.IsAny<Guid>(), It.IsAny<bool>(),
            It.IsAny<CancellationToken>()), Times.Never);
    }
}
