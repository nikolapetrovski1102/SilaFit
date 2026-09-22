using Moq;
using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class PlanServiceTests
{
    private readonly Mock<IPlansProvider> plansProvider = new(MockBehavior.Strict);
    private readonly Mock<ISubscriptionReceiptService> subscriptionReceiptService = new(MockBehavior.Strict);
    private readonly PlanService sut;

    public PlanServiceTests()
    {
        sut = new PlanService(plansProvider.Object, subscriptionReceiptService.Object);
    }

    [Fact]
    public async Task GetCatalogAsync_GroupsAndOrdersFeaturesByPlan()
    {
        var planA = new SubscriptionPlanModel { PlanId = Guid.NewGuid(), Code = "PRO", Name = "Pro" };
        var planB = new SubscriptionPlanModel { PlanId = Guid.NewGuid(), Code = "FREE", Name = "Free" };
        var features = new List<PlanFeatureModel>
        {
            new() { PlanId = planA.PlanId, FeatureText = "Second", SortOrder = 2 },
            new() { PlanId = planA.PlanId, FeatureText = "First", SortOrder = 1 },
            new() { PlanId = planB.PlanId, FeatureText = "Only", SortOrder = 1 }
        };
        plansProvider
            .Setup(p => p.GetAllAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync((new List<SubscriptionPlanModel> { planA, planB }, features));

        var result = await sut.GetCatalogAsync();

        Assert.True(result.IsSuccess);
        Assert.Equal(2, result.Data!.Count);
        var entryA = result.Data!.Single(e => e.Plan.PlanId == planA.PlanId);
        Assert.Equal(2, entryA.Features.Count);
        Assert.Equal("First", entryA.Features[0].FeatureText);
        Assert.Equal("Second", entryA.Features[1].FeatureText);
        var entryB = result.Data!.Single(e => e.Plan.PlanId == planB.PlanId);
        Assert.Single(entryB.Features);
    }

    [Fact]
    public async Task GetCurrentAsync_ActiveUnexpiredSubscription_ReturnsIt()
    {
        var userId = Guid.NewGuid();
        var subscription = new UserSubscriptionModel
        {
            UserId = userId,
            Status = "Active",
            ExpiresAtUtc = DateTime.UtcNow.AddDays(10),
            PlanCode = "PRO"
        };
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(subscription);

        var result = await sut.GetCurrentAsync(userId);

        Assert.True(result.IsSuccess);
        Assert.Equal("PRO", result.Data!.PlanCode);
        Assert.Equal("Active", result.Data!.Status);
    }

    [Fact]
    public async Task GetCurrentAsync_ActiveButExpiredSubscription_ReturnsFreeDefault()
    {
        var userId = Guid.NewGuid();
        var subscription = new UserSubscriptionModel
        {
            UserId = userId,
            Status = "Active",
            ExpiresAtUtc = DateTime.UtcNow.AddDays(-1),
            PlanCode = "PRO"
        };
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(subscription);

        var result = await sut.GetCurrentAsync(userId);

        Assert.True(result.IsSuccess);
        Assert.Equal("FREE", result.Data!.PlanCode);
        Assert.Equal("Inactive", result.Data!.Status);
        Assert.Equal(userId, result.Data!.UserId);
    }

    [Fact]
    public async Task GetCurrentAsync_NonActiveStatus_ReturnsFreeDefault()
    {
        var userId = Guid.NewGuid();
        var subscription = new UserSubscriptionModel
        {
            UserId = userId,
            Status = "Cancelled",
            ExpiresAtUtc = null,
            PlanCode = "PRO"
        };
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(subscription);

        var result = await sut.GetCurrentAsync(userId);

        Assert.True(result.IsSuccess);
        Assert.Equal("FREE", result.Data!.PlanCode);
    }

    [Fact]
    public async Task GetCurrentAsync_NoActiveSubscription_ReturnsFreeDefault()
    {
        var userId = Guid.NewGuid();
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync((UserSubscriptionModel?)null);

        var result = await sut.GetCurrentAsync(userId);

        Assert.True(result.IsSuccess);
        Assert.Equal("FREE", result.Data!.PlanCode);
        Assert.Equal("Free", result.Data!.PlanName);
        Assert.Equal(userId, result.Data!.UserId);
    }

    [Theory]
    [InlineData("Weekly")]
    [InlineData("")]
    [InlineData("monthly")]
    public async Task PurchaseAsync_UnsupportedBillingCycle_ReturnsValidationFailure(string billingCycle)
    {
        var userId = Guid.NewGuid();
        var request = new PurchaseRequest { PlanId = Guid.NewGuid(), BillingCycle = billingCycle };

        var result = await sut.PurchaseAsync(userId, request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task PurchaseAsync_ValidRequest_ReturnsProviderSubscription()
    {
        var userId = Guid.NewGuid();
        var planId = Guid.NewGuid();
        var request = new PurchaseRequest { PlanId = planId, BillingCycle = "Yearly" };
        var subscription = new UserSubscriptionModel { UserId = userId, PlanId = planId, BillingCycle = "Yearly", Status = "Active" };
        plansProvider
            .Setup(p => p.PurchaseAsync(userId, planId, "Yearly", It.IsAny<CancellationToken>()))
            .ReturnsAsync(subscription);

        var result = await sut.PurchaseAsync(userId, request);

        Assert.True(result.IsSuccess);
        Assert.Equal(planId, result.Data!.PlanId);
        Assert.Equal("Yearly", result.Data!.BillingCycle);
    }

    [Fact]
    public async Task PurchaseAsync_ProviderReturnsNull_ReturnsNotFoundFailure()
    {
        var userId = Guid.NewGuid();
        var planId = Guid.NewGuid();
        var request = new PurchaseRequest { PlanId = planId, BillingCycle = "Monthly" };
        plansProvider
            .Setup(p => p.PurchaseAsync(userId, planId, "Monthly", It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserSubscriptionModel?)null);

        var result = await sut.PurchaseAsync(userId, request);

        Assert.False(result.IsSuccess);
        Assert.Equal(404, result.StatusCode);
    }
}
