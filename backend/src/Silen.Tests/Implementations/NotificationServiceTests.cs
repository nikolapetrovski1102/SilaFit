using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Silen.Common.Dtos;
using Silen.Data.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class NotificationServiceTests
{
    private readonly Mock<INotificationProvider> notificationProvider = new(MockBehavior.Strict);
    private readonly NotificationService sut;

    public NotificationServiceTests()
    {
        sut = new NotificationService(notificationProvider.Object, NullLogger<NotificationService>.Instance);
    }

    [Fact]
    public async Task RegisterDeviceTokenAsync_ValidRequest_NormalizesPlatformTokenAndTimeZone()
    {
        var userId = Guid.NewGuid();
        var request = new RegisterDeviceTokenRequest
        {
            Token = "  abc123  ",
            Platform = "IOS",
            TimeZoneId = "Europe/Skopje",
            NotificationsEnabled = true
        };

        RegisterDeviceTokenRequest? captured = null;
        notificationProvider
            .Setup(p => p.RegisterDeviceTokenAsync(userId, It.IsAny<RegisterDeviceTokenRequest>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Callback<Guid, RegisterDeviceTokenRequest, DateTime, CancellationToken>((_, r, _, _) => captured = r)
            .Returns(Task.CompletedTask);

        var result = await sut.RegisterDeviceTokenAsync(userId, request);

        Assert.True(result.IsSuccess);
        Assert.NotNull(captured);
        Assert.Equal("abc123", captured!.Token);
        Assert.Equal("ios", captured.Platform);
        Assert.Equal("Europe/Skopje", captured.TimeZoneId);
    }

    [Fact]
    public async Task RegisterDeviceTokenAsync_TokenTooLong_ReturnsValidationFailureWithoutCallingProvider()
    {
        var request = new RegisterDeviceTokenRequest { Token = new string('a', 513) };

        var result = await sut.RegisterDeviceTokenAsync(Guid.NewGuid(), request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task RegisterDeviceTokenAsync_UnsupportedTimeZone_ReturnsValidationFailureWithoutCallingProvider()
    {
        var request = new RegisterDeviceTokenRequest { TimeZoneId = "Not/AZone" };

        var result = await sut.RegisterDeviceTokenAsync(Guid.NewGuid(), request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task RegisterDeviceTokenAsync_BlankPlatformTimeZoneAndToken_NormalizeToDefaults()
    {
        var userId = Guid.NewGuid();
        var request = new RegisterDeviceTokenRequest { Platform = "  ", TimeZoneId = null, Token = null };

        RegisterDeviceTokenRequest? captured = null;
        notificationProvider
            .Setup(p => p.RegisterDeviceTokenAsync(userId, It.IsAny<RegisterDeviceTokenRequest>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Callback<Guid, RegisterDeviceTokenRequest, DateTime, CancellationToken>((_, r, _, _) => captured = r)
            .Returns(Task.CompletedTask);

        var result = await sut.RegisterDeviceTokenAsync(userId, request);

        Assert.True(result.IsSuccess);
        Assert.Equal("unknown", captured!.Platform);
        Assert.Null(captured.TimeZoneId);
        Assert.Null(captured.Token);
    }

    [Fact]
    public async Task DeactivateDeviceTokenAsync_ValidToken_Succeeds()
    {
        var userId = Guid.NewGuid();
        var request = new DeactivateDeviceTokenRequest { Token = "tok" };
        notificationProvider.Setup(p => p.DeactivateDeviceTokenAsync(userId, "tok", It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.DeactivateDeviceTokenAsync(userId, request);

        Assert.True(result.IsSuccess);
    }

    [Fact]
    public async Task DeactivateDeviceTokenAsync_BlankToken_ReturnsValidationFailureWithoutCallingProvider()
    {
        var request = new DeactivateDeviceTokenRequest { Token = "   " };

        var result = await sut.DeactivateDeviceTokenAsync(Guid.NewGuid(), request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task RecordInteractionAsync_WithTimeZone_RefreshesDeviceTimeZoneThenRecordsInteraction()
    {
        var userId = Guid.NewGuid();
        var notificationId = Guid.NewGuid();
        var request = new RecordNotificationInteractionRequest { NotificationId = notificationId, TimeZoneId = "Europe/Skopje" };

        notificationProvider
            .Setup(p => p.RegisterDeviceTokenAsync(userId, It.Is<RegisterDeviceTokenRequest>(r => r.TimeZoneId == "Europe/Skopje"), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        notificationProvider
            .Setup(p => p.RecordInteractionAsync(userId, It.IsAny<DateTime>(), notificationId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RecordInteractionAsync(userId, request);

        Assert.True(result.IsSuccess);
        notificationProvider.Verify(
            p => p.RegisterDeviceTokenAsync(userId, It.IsAny<RegisterDeviceTokenRequest>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Fact]
    public async Task RecordInteractionAsync_WithoutTimeZone_OnlyRecordsInteraction()
    {
        var userId = Guid.NewGuid();
        var request = new RecordNotificationInteractionRequest { TimeZoneId = null };

        notificationProvider
            .Setup(p => p.RecordInteractionAsync(userId, It.IsAny<DateTime>(), null, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RecordInteractionAsync(userId, request);

        Assert.True(result.IsSuccess);
        notificationProvider.Verify(
            p => p.RegisterDeviceTokenAsync(It.IsAny<Guid>(), It.IsAny<RegisterDeviceTokenRequest>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()),
            Times.Never);
    }

    [Fact]
    public async Task RecordWorkoutHeartbeatAsync_Succeeds_AndForwardsSessionId()
    {
        var userId = Guid.NewGuid();
        var sessionId = Guid.NewGuid();
        notificationProvider
            .Setup(p => p.RecordWorkoutHeartbeatAsync(userId, sessionId, It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RecordWorkoutHeartbeatAsync(userId, sessionId);

        Assert.True(result.IsSuccess);
    }
}
