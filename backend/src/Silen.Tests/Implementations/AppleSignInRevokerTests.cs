using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Security.Cryptography;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Moq;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class AppleSignInRevokerTests
{
    private readonly Mock<IAccountProvider> accountProvider = new(MockBehavior.Strict);
    private readonly StubHandler handler = new();

    private AppleSignInRevoker CreateSut(bool configured)
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var options = new AppleAuthOptions { ClientIds = ["com.example.app"] };
        if (configured)
        {
            options.TeamId = "TEAM123";
            options.KeyId = "KEY123";
            options.PrivateKey = key.ExportPkcs8PrivateKeyPem();
        }

        return new AppleSignInRevoker(
            new HttpClient(handler), Options.Create(options), accountProvider.Object, NullLogger<AppleSignInRevoker>.Instance);
    }

    [Fact]
    public async Task StoreAuthorizationAsync_ExchangesCodeAndStoresRefreshToken()
    {
        var userId = Guid.NewGuid();
        handler.Response = new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent("""{"access_token":"a","refresh_token":"r-token","id_token":"i"}""")
        };
        accountProvider.Setup(p => p.SetAppleRefreshTokenAsync(userId, "r-token", It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        await CreateSut(configured: true).StoreAuthorizationAsync(userId, "code-1");

        Assert.Equal("https://appleid.apple.com/auth/token", handler.LastRequestUri);
        Assert.Equal("authorization_code", handler.LastForm!["grant_type"]);
        Assert.Equal("code-1", handler.LastForm["code"]);
        Assert.Equal("com.example.app", handler.LastForm["client_id"]);

        var secret = new JwtSecurityTokenHandler().ReadJwtToken(handler.LastForm["client_secret"]);
        Assert.Equal("TEAM123", secret.Issuer);
        Assert.Equal("KEY123", secret.Header.Kid);
        Assert.Equal("ES256", secret.Header.Alg);
        Assert.Equal("com.example.app", secret.Subject);
        Assert.Contains("https://appleid.apple.com", secret.Audiences);
        accountProvider.VerifyAll();
    }

    [Fact]
    public async Task StoreAuthorizationAsync_AppleRejectsCode_StoresNothingAndDoesNotThrow()
    {
        handler.Response = new HttpResponseMessage(HttpStatusCode.BadRequest) { Content = new StringContent("""{"error":"invalid_grant"}""") };

        await CreateSut(configured: true).StoreAuthorizationAsync(Guid.NewGuid(), "stale-code");

        accountProvider.Verify(p => p.SetAppleRefreshTokenAsync(It.IsAny<Guid>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task StoreAuthorizationAsync_NotConfigured_MakesNoCalls()
    {
        await CreateSut(configured: false).StoreAuthorizationAsync(Guid.NewGuid(), "code-1");

        Assert.Null(handler.LastRequestUri);
    }

    [Fact]
    public async Task RevokeAsync_WithStoredToken_PostsItToAppleRevoke()
    {
        var userId = Guid.NewGuid();
        accountProvider.Setup(p => p.GetAppleRefreshTokenAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync("r-token");
        handler.Response = new HttpResponseMessage(HttpStatusCode.OK);

        await CreateSut(configured: true).RevokeAsync(userId);

        Assert.Equal("https://appleid.apple.com/auth/revoke", handler.LastRequestUri);
        Assert.Equal("r-token", handler.LastForm!["token"]);
        Assert.Equal("refresh_token", handler.LastForm["token_type_hint"]);
    }

    [Fact]
    public async Task RevokeAsync_NoStoredToken_MakesNoHttpCall()
    {
        var userId = Guid.NewGuid();
        accountProvider.Setup(p => p.GetAppleRefreshTokenAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((string?)null);

        await CreateSut(configured: true).RevokeAsync(userId);

        Assert.Null(handler.LastRequestUri);
    }

    [Fact]
    public async Task RevokeAsync_AppleUnreachable_DoesNotThrow()
    {
        var userId = Guid.NewGuid();
        accountProvider.Setup(p => p.GetAppleRefreshTokenAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync("r-token");
        handler.Exception = new HttpRequestException("network down");

        await CreateSut(configured: true).RevokeAsync(userId);
    }

    private sealed class StubHandler : HttpMessageHandler
    {
        public HttpResponseMessage Response { get; set; } = new(HttpStatusCode.OK);
        public Exception? Exception { get; set; }
        public string? LastRequestUri { get; private set; }
        public Dictionary<string, string>? LastForm { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            LastRequestUri = request.RequestUri!.ToString();
            var body = await request.Content!.ReadAsStringAsync(cancellationToken);
            LastForm = body.Split('&')
                .Select(pair => pair.Split('=', 2))
                .ToDictionary(kv => WebUtility.UrlDecode(kv[0]), kv => WebUtility.UrlDecode(kv[1]));
            if (Exception is not null)
            {
                throw Exception;
            }

            return Response;
        }
    }
}
