using System.Net;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Moq;
using Silen.Common.Dtos;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class DownloadLinkServiceTests
{
    private const string IphoneInstagramUa =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 350.0.0";

    private readonly Mock<IDownloadLinksProvider> provider = new(MockBehavior.Strict);
    private readonly DownloadLinkService sut;

    public DownloadLinkServiceTests()
    {
        sut = new DownloadLinkService(
            provider.Object,
            Mock.Of<IAdminProvider>(),
            Mock.Of<IAdminRbacProvider>(),
            Options.Create(new JwtOptions { SigningKey = "test-signing-key-test-signing-key" }),
            NullLogger<DownloadLinkService>.Instance);
    }

    [Fact]
    public async Task RecordVisitAsync_PhoneVisit_StoresNormalizedSourceDeviceAndNetworkHash()
    {
        byte[]? storedHash = null;
        provider.Setup(p => p.RecordVisitAsync(
                "crooks-gym", It.IsAny<Guid?>(), "ios", "iPhone · iOS 18.1 · Instagram app",
                It.IsAny<byte[]?>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .Callback<string?, Guid?, string, string?, byte[]?, int, CancellationToken>((_, _, _, _, h, _, _) => storedHash = h)
            .Returns(Task.CompletedTask);

        var result = await sut.RecordVisitAsync(
            new DownloadVisitRequest { Source = " Crooks-Gym ", Platform = "iOS", VisitorId = Guid.NewGuid() },
            IPAddress.Parse("89.205.10.20"),
            IphoneInstagramUa);

        Assert.True(result.IsSuccess);
        Assert.NotNull(storedHash);
        Assert.Equal(32, storedHash!.Length);
        Assert.NotEqual(IPAddress.Parse("89.205.10.20").GetAddressBytes(), storedHash);
    }

    [Fact]
    public async Task RecordVisitAsync_DesktopVisit_KeepsNoNetworkHash()
    {
        provider.Setup(p => p.RecordVisitAsync(
                "social-media-tiktok", null, "desktop", "Mac", null, It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RecordVisitAsync(
            new DownloadVisitRequest { Source = "social-media-tiktok", Platform = "desktop" },
            IPAddress.Parse("89.205.10.20"),
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)");

        Assert.True(result.IsSuccess);
        provider.VerifyAll();
    }

    [Theory]
    [InlineData("<script>")]
    [InlineData("crooks gym")]
    [InlineData("")]
    public async Task RecordVisitAsync_MalformedSource_IsRecordedAsUntagged(string source)
    {
        provider.Setup(p => p.RecordVisitAsync(
                null, It.IsAny<Guid?>(), "android", It.IsAny<string?>(), It.IsAny<byte[]?>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RecordVisitAsync(
            new DownloadVisitRequest { Source = source, Platform = "android" },
            IPAddress.Parse("10.0.0.1"),
            "Mozilla/5.0 (Linux; Android 14; Pixel 8)");

        Assert.True(result.IsSuccess);
        provider.VerifyAll();
    }

    [Fact]
    public async Task RecordVisitAsync_UnknownPlatform_IsRejected()
    {
        var result = await sut.RecordVisitAsync(
            new DownloadVisitRequest { Source = "crooks-gym", Platform = "fridge" }, IPAddress.Loopback, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task ClaimInstall_MatchesTheHashTheVisitStored_AcrossIpv6PrivacyAddresses()
    {
        byte[]? visitHash = null, claimHash = null;
        provider.Setup(p => p.RecordVisitAsync(
                It.IsAny<string?>(), It.IsAny<Guid?>(), "ios", It.IsAny<string?>(), It.IsAny<byte[]?>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .Callback<string?, Guid?, string, string?, byte[]?, int, CancellationToken>((_, _, _, _, h, _, _) => visitHash = h)
            .Returns(Task.CompletedTask);
        provider.Setup(p => p.ClaimInstallAsync(
                It.IsAny<Guid>(), It.IsAny<byte[]>(), "ios", It.IsAny<int>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .Callback<Guid, byte[], string?, int, int, CancellationToken>((_, h, _, _, _, _) => claimHash = h)
            .ReturnsAsync((true, "crooks-gym"));

        // Same /64, different interface id - what one phone does between Safari and the app.
        await sut.RecordVisitAsync(
            new DownloadVisitRequest { Source = "crooks-gym", Platform = "ios" },
            IPAddress.Parse("2a02:2b88:6:1d2::1111"), IphoneInstagramUa);
        await sut.ClaimInstallAsync(Guid.NewGuid(), IPAddress.Parse("2a02:2b88:6:1d2:abcd::9"), "ios");

        Assert.NotNull(visitHash);
        Assert.Equal(visitHash, claimHash);
    }

    [Fact]
    public async Task ClaimInstall_ProviderFailure_NeverThrows()
    {
        provider.Setup(p => p.ClaimInstallAsync(
                It.IsAny<Guid>(), It.IsAny<byte[]>(), null, It.IsAny<int>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("database down"));

        await sut.ClaimInstallAsync(Guid.NewGuid(), IPAddress.Parse("89.205.10.20"), platform: "windows");
    }

    [Theory]
    [InlineData("Mozilla/5.0 (Linux; Android 14; SM-S918B) Chrome/129.0 Mobile", "Android 14")]
    [InlineData("Mozilla/5.0 (iPad; CPU OS 17_6 like Mac OS X) Safari/604.1", "iPad · iOS 17.6")]
    [InlineData("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) musical_ly_37.1.0", "iPhone · iOS 18.0 · TikTok app")]
    [InlineData("Mozilla/5.0 (Windows NT 10.0; Win64; x64)", "Windows")]
    public async Task RecordVisitAsync_StoresAShortDeviceLabel(string userAgent, string expected)
    {
        provider.Setup(p => p.RecordVisitAsync(
                It.IsAny<string?>(), It.IsAny<Guid?>(), "desktop", expected, null, It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RecordVisitAsync(
            new DownloadVisitRequest { Platform = "desktop" }, IPAddress.Loopback, userAgent);

        Assert.True(result.IsSuccess);
        provider.VerifyAll();
    }
}
