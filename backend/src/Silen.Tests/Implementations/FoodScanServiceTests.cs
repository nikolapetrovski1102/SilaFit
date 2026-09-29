using System.Text.Json;
using Microsoft.Extensions.Options;
using Moq;
using Silen.Common.Exceptions;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class FoodScanServiceTests
{
    private static readonly byte[] Jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];

    private readonly Mock<ISubscriptionGate> subscriptionGate = new(MockBehavior.Strict);
    private readonly Mock<IUserSettingsProvider> userSettingsProvider = new(MockBehavior.Strict);
    private readonly Mock<IFoodScanProvider> foodScanProvider = new(MockBehavior.Strict);
    private readonly Mock<IOpenRouterClient> openRouterClient = new(MockBehavior.Strict);
    private readonly FoodScanService sut;
    private readonly Guid userId = Guid.NewGuid();

    public FoodScanServiceTests()
    {
        sut = new FoodScanService(
            subscriptionGate.Object, userSettingsProvider.Object, foodScanProvider.Object, openRouterClient.Object,
            Options.Create(new OpenRouterOptions { FoodScanModel = "test/vision" }));

        subscriptionGate.Setup(g => g.HasActiveAdvancedAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(true);
        userSettingsProvider
            .Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new UserSettingsModel { UserId = userId, AiDataConsentAtUtc = DateTime.UtcNow });
    }

    private void AllowReservation(int usedAfter = 1, long foodScanId = 42) =>
        foodScanProvider
            .Setup(p => p.TryReserveAsync(userId, It.IsAny<DateTime>(), FoodScanService.DailyScanLimit, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new FoodScanReservationModel { Allowed = true, UsedToday = usedAfter, FoodScanId = foodScanId });

    private void AiReturns(object response) =>
        openRouterClient
            .Setup(c => c.GenerateJsonFromImageAsync(
                It.IsAny<string>(), It.IsAny<string>(), Jpeg, "image/jpeg", It.IsAny<JsonElement>(),
                "test/vision", It.IsAny<string>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(JsonSerializer.Serialize(response));

    private static object Item(
        string name, decimal grams, decimal kcal, decimal protein, decimal carbs, decimal fat,
        bool assumed = false, string confidence = "high") =>
        new
        {
            name, grams, kcalPer100g = kcal, proteinPer100g = protein, carbsPer100g = carbs, fatPer100g = fat,
            fiberPer100g = 0m, assumed, confidence
        };

    [Fact]
    public async Task ScanAsync_WithoutAdvanced_ReturnsForbiddenWithoutReservingOrCallingAi()
    {
        subscriptionGate.Setup(g => g.HasActiveAdvancedAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(false);

        var result = await sut.ScanAsync(userId, Jpeg, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(403, result.StatusCode);
        foodScanProvider.VerifyNoOtherCalls();
        openRouterClient.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task ScanAsync_WithoutAiConsent_ReturnsConsentRequired()
    {
        userSettingsProvider
            .Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new UserSettingsModel { UserId = userId, AiDataConsentAtUtc = null });

        var result = await sut.ScanAsync(userId, Jpeg, null);

        Assert.Equal(428, result.StatusCode);
        foodScanProvider.VerifyNoOtherCalls();
        openRouterClient.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task ScanAsync_NotAnImage_ReturnsValidationFailureWithoutUsingAScan()
    {
        var result = await sut.ScanAsync(userId, "GIF89a"u8.ToArray(), null);

        Assert.Equal(400, result.StatusCode);
        foodScanProvider.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task ScanAsync_DailyAllowanceSpent_ReturnsTooManyRequestsWithoutCallingAi()
    {
        foodScanProvider
            .Setup(p => p.TryReserveAsync(userId, It.IsAny<DateTime>(), FoodScanService.DailyScanLimit, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new FoodScanReservationModel { Allowed = false, UsedToday = 3 });

        var result = await sut.ScanAsync(userId, Jpeg, null);

        Assert.Equal(429, result.StatusCode);
        openRouterClient.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task ScanAsync_AiFails_GivesTheScanBack()
    {
        AllowReservation(foodScanId: 7);
        openRouterClient
            .Setup(c => c.GenerateJsonFromImageAsync(
                It.IsAny<string>(), It.IsAny<string>(), It.IsAny<byte[]>(), It.IsAny<string>(), It.IsAny<JsonElement>(),
                It.IsAny<string>(), It.IsAny<string>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new ConflictException("OpenRouter API returned status 502."));
        foodScanProvider.Setup(p => p.ReleaseAsync(userId, 7, It.IsAny<CancellationToken>())).Returns(Task.CompletedTask);

        var result = await sut.ScanAsync(userId, Jpeg, null);

        Assert.Equal(409, result.StatusCode);
        foodScanProvider.Verify(p => p.ReleaseAsync(userId, 7, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ScanAsync_Success_ReturnsItemsAndRemainingAllowance()
    {
        AllowReservation(usedAfter: 2);
        AiReturns(new
        {
            isFood = true,
            dishName = "Chicken and rice",
            notes = "",
            items = new[]
            {
                Item("Chicken breast, grilled", 150, 165, 31, 0, 3.6m),
                Item("Olive oil", 5, 884, 0, 0, 100, assumed: true, confidence: "medium")
            }
        });

        var result = await sut.ScanAsync(userId, Jpeg, "Lunch");

        Assert.True(result.IsSuccess);
        var scan = result.Data!;
        Assert.True(scan.IsFood);
        Assert.Equal("Chicken and rice", scan.DishName);
        Assert.Equal(2, scan.Items.Count);
        Assert.Equal(150, scan.Items[0].EstimatedGrams);
        Assert.Equal(31, scan.Items[0].ProteinG);
        Assert.True(scan.Items[1].IsAssumed);
        Assert.Equal(1, scan.Quota.RemainingToday);
    }

    [Fact]
    public async Task ScanAsync_ImplausibleNumbers_AreClampedToRealFoodLimits()
    {
        AllowReservation();
        AiReturns(new
        {
            isFood = true,
            dishName = "Mystery",
            notes = "",
            items = new[] { Item("Mystery bar", 99999, 5000, 80, 80, 40, confidence: "certain") }
        });

        var result = await sut.ScanAsync(userId, Jpeg, null);

        var item = Assert.Single(result.Data!.Items);
        Assert.Equal(2000, item.EstimatedGrams);
        Assert.Equal(900, item.CaloriesKcal);
        Assert.True(item.ProteinG + item.CarbohydrateG + item.FatG <= 100.1m);
        Assert.Equal("medium", item.Confidence);
    }

    [Fact]
    public async Task ScanAsync_NotFood_ReturnsNoItems()
    {
        AllowReservation();
        AiReturns(new { isFood = false, dishName = "", notes = "", items = Array.Empty<object>() });

        var result = await sut.ScanAsync(userId, Jpeg, null);

        Assert.True(result.IsSuccess);
        Assert.False(result.Data!.IsFood);
        Assert.Empty(result.Data.Items);
    }

    [Fact]
    public async Task ScanAsync_CountsTheDayFromTheUsersLocalMidnight()
    {
        userSettingsProvider
            .Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new UserSettingsModel { UserId = userId, AiDataConsentAtUtc = DateTime.UtcNow, TimeZoneId = "+05:00" });
        DateTime? dayStartUtc = null;
        foodScanProvider
            .Setup(p => p.TryReserveAsync(userId, It.IsAny<DateTime>(), FoodScanService.DailyScanLimit, It.IsAny<CancellationToken>()))
            .Callback((Guid _, DateTime start, int _, CancellationToken _) => dayStartUtc = start)
            .ReturnsAsync(new FoodScanReservationModel { Allowed = false, UsedToday = 3 });

        await sut.ScanAsync(userId, Jpeg, null);

        // Local midnight in UTC+5 is 19:00 UTC the previous day.
        Assert.Equal(19, dayStartUtc!.Value.Hour);
        Assert.Equal(0, dayStartUtc.Value.Minute);
        Assert.True(DateTime.UtcNow - dayStartUtc.Value < TimeSpan.FromDays(1));
    }

    [Fact]
    public async Task GetQuotaAsync_BelowAdvanced_IsUnavailable()
    {
        subscriptionGate.Setup(g => g.HasActiveAdvancedAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(false);

        var result = await sut.GetQuotaAsync(userId);

        Assert.True(result.IsSuccess);
        Assert.False(result.Data!.IsAvailable);
        foodScanProvider.VerifyNoOtherCalls();
    }
}
