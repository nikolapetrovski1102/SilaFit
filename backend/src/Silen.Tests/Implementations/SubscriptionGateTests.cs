using Microsoft.Extensions.Configuration;
using Moq;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class SubscriptionGateTests
{
    private readonly Mock<IPlansProvider> plansProvider = new(MockBehavior.Strict);
    private string? devTiersFreeValue;

    private SubscriptionGate Sut()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(devTiersFreeValue is null
                ? []
                : new Dictionary<string, string?> { ["FeatureFlags:DevTiersFree"] = devTiersFreeValue })
            .Build();
        return new(plansProvider.Object, configuration);
    }

    private void SetDevTiersFree(string? value) => devTiersFreeValue = value;

    private static UserSubscriptionModel Subscription(string status, string? planCode, DateTime? expiresAtUtc) => new()
    {
        UserId = Guid.NewGuid(),
        PlanId = Guid.NewGuid(),
        BillingCycle = "Monthly",
        Status = status,
        StartedAtUtc = DateTime.UtcNow.AddMonths(-1),
        ExpiresAtUtc = expiresAtUtc,
        PlanCode = planCode
    };

    [Fact]
    public async Task HasActiveProAsync_DevTiersFreeEnabled_ReturnsTrueWithoutQueryingProvider()
    {
        SetDevTiersFree("true");

        var result = await Sut().HasActiveProAsync(Guid.NewGuid());

        Assert.True(result);
    }

    [Fact]
    public async Task HasActiveProAsync_ActiveProSubscription_ReturnsTrue()
    {
        SetDevTiersFree(null);
        var userId = Guid.NewGuid();
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Subscription("Active", "PRO", DateTime.UtcNow.AddDays(10)));

        var result = await Sut().HasActiveProAsync(userId);

        Assert.True(result);
    }

    [Fact]
    public async Task HasActiveProAsync_ActiveAdvancedSubscription_AlsoCountsAsPro()
    {
        SetDevTiersFree(null);
        var userId = Guid.NewGuid();
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Subscription("Active", "ADVANCED", DateTime.UtcNow.AddDays(10)));

        var result = await Sut().HasActiveProAsync(userId);

        Assert.True(result);
    }

    [Fact]
    public async Task HasActiveProAsync_NoSubscription_ReturnsFalse()
    {
        SetDevTiersFree(null);
        var userId = Guid.NewGuid();
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserSubscriptionModel?)null);

        var result = await Sut().HasActiveProAsync(userId);

        Assert.False(result);
    }

    [Fact]
    public async Task HasActiveProAsync_InactiveStatus_ReturnsFalse()
    {
        SetDevTiersFree(null);
        var userId = Guid.NewGuid();
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Subscription("Cancelled", "PRO", DateTime.UtcNow.AddDays(10)));

        var result = await Sut().HasActiveProAsync(userId);

        Assert.False(result);
    }

    [Fact]
    public async Task HasActiveProAsync_ExpiredSubscription_ReturnsFalse()
    {
        SetDevTiersFree(null);
        var userId = Guid.NewGuid();
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Subscription("Active", "PRO", DateTime.UtcNow.AddDays(-1)));

        var result = await Sut().HasActiveProAsync(userId);

        Assert.False(result);
    }

    [Fact]
    public async Task HasActiveProAsync_NullExpiry_NeverExpires_ReturnsTrue()
    {
        SetDevTiersFree(null);
        var userId = Guid.NewGuid();
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Subscription("Active", "PRO", null));

        var result = await Sut().HasActiveProAsync(userId);

        Assert.True(result);
    }

    [Fact]
    public async Task HasActiveProAsync_FreePlanCode_ReturnsFalse()
    {
        SetDevTiersFree(null);
        var userId = Guid.NewGuid();
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Subscription("Active", "FREE", null));

        var result = await Sut().HasActiveProAsync(userId);

        Assert.False(result);
    }

    [Fact]
    public async Task HasActiveAdvancedAsync_ProOnlySubscription_ReturnsFalse()
    {
        SetDevTiersFree(null);
        var userId = Guid.NewGuid();
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Subscription("Active", "PRO", null));

        var result = await Sut().HasActiveAdvancedAsync(userId);

        Assert.False(result);
    }

    [Fact]
    public async Task HasActiveAdvancedAsync_AdvancedSubscription_ReturnsTrue()
    {
        SetDevTiersFree(null);
        var userId = Guid.NewGuid();
        plansProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Subscription("Active", "ADVANCED", null));

        var result = await Sut().HasActiveAdvancedAsync(userId);

        Assert.True(result);
    }

    [Fact]
    public async Task HasActiveAdvancedAsync_DevTiersFreeEnabled_ReturnsTrueWithoutQueryingProvider()
    {
        SetDevTiersFree("true");

        var result = await Sut().HasActiveAdvancedAsync(Guid.NewGuid());

        Assert.True(result);
    }
}
