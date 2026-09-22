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
        AppearanceMode = "Dark",
        AvatarChoice = "Male"
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

    [Fact]
    public async Task UpdateAsync_UnsupportedAvatarChoice_ReturnsValidationFailureWithoutCallingProvider()
    {
        var request = ValidRequest();
        request.AvatarChoice = "Nonbinary";

        var result = await sut.UpdateAsync(Guid.NewGuid(), request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Theory]
    [InlineData("Female")]
    [InlineData("Male1")]
    [InlineData("Male9")]
    [InlineData("Female1")]
    [InlineData("Female9")]
    public async Task UpdateAsync_IllustratedAvatarChoice_ReturnsUpdatedSettings(string avatarChoice)
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        request.AvatarChoice = avatarChoice;
        var updated = new UserSettingsModel { UserId = userId, WeightUnit = "kg" };
        userSettingsProvider.Setup(p => p.UpdateAsync(userId, request, It.IsAny<CancellationToken>())).ReturnsAsync(updated);

        var result = await sut.UpdateAsync(userId, request);

        Assert.True(result.IsSuccess);
        Assert.Same(updated, result.Data);
    }

    [Fact]
    public async Task UpdateAsync_InvalidNotificationTime_ReturnsValidationFailureWithoutCallingProvider()
    {
        var request = ValidRequest();
        request.NotificationLocalTime = TimeSpan.FromHours(24);

        var result = await sut.UpdateAsync(Guid.NewGuid(), request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
        userSettingsProvider.Verify(
            p => p.UpdateAsync(It.IsAny<Guid>(), It.IsAny<UpdateUserSettingsRequest>(), It.IsAny<CancellationToken>()),
            Times.Never);
    }

    [Fact]
    public async Task UpdateAsync_InvalidTimeZone_ReturnsValidationFailureWithoutCallingProvider()
    {
        var request = ValidRequest();
        request.TimeZoneId = "Definitely/Not-A-TimeZone";

        var result = await sut.UpdateAsync(Guid.NewGuid(), request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
        userSettingsProvider.Verify(
            p => p.UpdateAsync(It.IsAny<Guid>(), It.IsAny<UpdateUserSettingsRequest>(), It.IsAny<CancellationToken>()),
            Times.Never);
    }

    [Fact]
    public async Task UpdateAsync_FixedOffsetTimeZone_IsCanonicalizedBeforeSaving()
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        request.TimeZoneId = "+0545";
        var updated = new UserSettingsModel { UserId = userId, TimeZoneId = "+05:45" };
        userSettingsProvider
            .Setup(p => p.UpdateAsync(
                userId,
                It.Is<UpdateUserSettingsRequest>(r => r.TimeZoneId == "+05:45"),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(updated);

        var result = await sut.UpdateAsync(userId, request);

        Assert.True(result.IsSuccess);
        Assert.Equal("+05:45", request.TimeZoneId);
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
