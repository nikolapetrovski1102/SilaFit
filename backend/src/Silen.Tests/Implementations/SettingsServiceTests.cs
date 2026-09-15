using Moq;
using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class SettingsServiceTests
{
    private readonly Mock<IUserSettingsProvider> userSettingsProvider = new(MockBehavior.Strict);
    private readonly SettingsService sut;

    public SettingsServiceTests()
    {
        sut = new SettingsService(userSettingsProvider.Object);
    }

    private static UpdateUserSettingsRequest ValidRequest() => new()
    {
        TargetWaterMl = 2500,
        NotificationsEnabled = true,
        NotificationLocalTime = TimeSpan.FromHours(18),
        TimeZoneId = "UTC",
        WeightUnit = "kg",
        DistanceUnit = "km",
        RestTimerSoundEnabled = true,
        BarbellStandardKg = 20,
        AppearanceMode = "Dark"
    };

    [Fact]
    public async Task GetAsync_SettingsExist_ReturnsSuccessWithData()
    {
        var userId = Guid.NewGuid();
        var model = new UserSettingsModel { UserId = userId, WeightUnit = "kg" };
        userSettingsProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(model);

        var result = await sut.GetAsync(userId);

        Assert.True(result.IsSuccess);
        Assert.Same(model, result.Data);
    }

    [Fact]
    public async Task GetAsync_SettingsMissing_ReturnsNotFoundFailure()
    {
        var userId = Guid.NewGuid();
        userSettingsProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync((UserSettingsModel?)null);

        var result = await sut.GetAsync(userId);

        Assert.False(result.IsSuccess);
        Assert.Equal(404, result.StatusCode);
    }

    [Fact]
    public async Task UpdateAsync_ValidRequest_ReturnsUpdatedSettings()
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        var updated = new UserSettingsModel { UserId = userId, WeightUnit = "kg" };
        userSettingsProvider.Setup(p => p.UpdateAsync(userId, request, It.IsAny<CancellationToken>())).ReturnsAsync(updated);

        var result = await sut.UpdateAsync(userId, request);

        Assert.True(result.IsSuccess);
        Assert.Same(updated, result.Data);
    }

    [Fact]
    public async Task UpdateAsync_ProviderReturnsNull_ReturnsNotFoundFailure()
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        userSettingsProvider.Setup(p => p.UpdateAsync(userId, request, It.IsAny<CancellationToken>())).ReturnsAsync((UserSettingsModel?)null);

        var result = await sut.UpdateAsync(userId, request);

        Assert.False(result.IsSuccess);
        Assert.Equal(404, result.StatusCode);
    }

    [Theory]
    [InlineData("oz")]
    [InlineData("")]
    public async Task UpdateAsync_UnsupportedWeightUnit_ReturnsValidationFailureWithoutCallingProvider(string weightUnit)
    {
        var request = ValidRequest();
        request.WeightUnit = weightUnit;

        var result = await sut.UpdateAsync(Guid.NewGuid(), request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task UpdateAsync_UnsupportedDistanceUnit_ReturnsValidationFailureWithoutCallingProvider()
    {
        var request = ValidRequest();
        request.DistanceUnit = "furlongs";

        var result = await sut.UpdateAsync(Guid.NewGuid(), request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task UpdateAsync_UnsupportedAppearanceMode_ReturnsValidationFailureWithoutCallingProvider()
    {
        var request = ValidRequest();
        request.AppearanceMode = "Rainbow";

        var result = await sut.UpdateAsync(Guid.NewGuid(), request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-5)]
    public async Task UpdateAsync_NonPositiveBarbellStandard_ReturnsValidationFailureWithoutCallingProvider(decimal barbellKg)
    {
        var request = ValidRequest();
        request.BarbellStandardKg = barbellKg;

        var result = await sut.UpdateAsync(Guid.NewGuid(), request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public async Task UpdateAsync_NonPositiveTargetWater_ReturnsValidationFailureWithoutCallingProvider(int targetWaterMl)
    {
        var request = ValidRequest();
        request.TargetWaterMl = targetWaterMl;

        var result = await sut.UpdateAsync(Guid.NewGuid(), request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }
}
