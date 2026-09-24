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

    private void SetupAppStoreTransaction() =>
        appStoreClient.Setup(c => c.GetTransactionInfoAsync(TransactionId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AppStoreTransactionInfo
            {
                TransactionId = TransactionId,
                OriginalTransactionId = OriginalTransactionId,
                ProductId = MonthlyProductId,
                ExpiresAtUtc = DateTime.UtcNow.AddDays(20),
                RawPayloadJson = "{}"
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
}
