using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Moq;
using Silen.Common.Options;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class FcmPushNotificationSenderTests
{
    private readonly Mock<IHttpClientFactory> httpClientFactory = new(MockBehavior.Strict);

    private const string ValidServiceAccountJson =
        """
        {"client_email":"svc@proj.iam.gserviceaccount.com","private_key":"-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----\n","project_id":"proj123","private_key_id":"key-1"}
        """;

    private FcmPushNotificationSender Sut(PushNotificationOptions options) =>
        new(httpClientFactory.Object, Options.Create(options), NullLogger<FcmPushNotificationSender>.Instance);

    [Theory]
    [InlineData(false, "", "", false)]
    [InlineData(true, "", "", false)]
    [InlineData(true, "{\"some\":\"json\"}", "", true)]
    [InlineData(true, "", "/some/path.json", true)]
    public void CanConfigure_ReflectsEnabledAndServiceAccountPresence(bool enabled, string json, string path, bool expected)
    {
        var options = new PushNotificationOptions { Enabled = enabled, ServiceAccountJson = json, ServiceAccountJsonPath = path };

        Assert.Equal(expected, FcmPushNotificationSender.CanConfigure(options));
    }

    [Fact]
    public void IsConfigured_Disabled_False()
    {
        var sut = Sut(new PushNotificationOptions { Enabled = false });

        Assert.False(sut.IsConfigured);
    }

    [Fact]
    public void IsConfigured_EnabledButNoServiceAccount_False()
    {
        var sut = Sut(new PushNotificationOptions { Enabled = true });

        Assert.False(sut.IsConfigured);
    }

    [Fact]
    public void IsConfigured_MalformedJson_False()
    {
        var sut = Sut(new PushNotificationOptions { Enabled = true, ServiceAccountJson = "{not valid json" });

        Assert.False(sut.IsConfigured);
    }

    [Fact]
    public void IsConfigured_JsonMissingRequiredFields_False()
    {
        var sut = Sut(new PushNotificationOptions { Enabled = true, ServiceAccountJson = """{"client_email":"only@this.com"}""" });

        Assert.False(sut.IsConfigured);
    }

    [Fact]
    public void IsConfigured_ValidInlineJson_True()
    {
        var sut = Sut(new PushNotificationOptions { Enabled = true, ServiceAccountJson = ValidServiceAccountJson });

        Assert.True(sut.IsConfigured);
    }

    [Fact]
    public void IsConfigured_ValidJsonFromPath_True()
    {
        var path = Path.GetTempFileName();
        try
        {
            File.WriteAllText(path, ValidServiceAccountJson);
            var sut = Sut(new PushNotificationOptions { Enabled = true, ServiceAccountJsonPath = path });

            Assert.True(sut.IsConfigured);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void IsConfigured_UnreadablePath_False()
    {
        var sut = Sut(new PushNotificationOptions { Enabled = true, ServiceAccountJsonPath = "/nonexistent/does-not-exist.json" });

        Assert.False(sut.IsConfigured);
    }

    [Fact]
    public async Task SendAsync_NotConfigured_ReturnsFailedWithoutTouchingHttpFactory()
    {
        var sut = Sut(new PushNotificationOptions { Enabled = false });

        var result = await sut.SendAsync(new Silen.Common.Models.PushNotificationMessage
        {
            Token = "device-token",
            Title = "Hi",
            Body = "There"
        });

        Assert.False(result.Success);
        Assert.False(result.TokenInvalid);
    }
}
