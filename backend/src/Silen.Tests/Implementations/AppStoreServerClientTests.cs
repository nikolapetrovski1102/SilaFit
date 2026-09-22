using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Security.Cryptography;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Silen.Common.Options;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

// Only the outbound JWT construction is covered here - the one genuinely new
// crypto piece in AppStoreServerClient. A fake HttpMessageHandler captures the
// Authorization header GetTransactionInfoAsync sends without ever hitting the
// network; the response body it returns is irrelevant to this test.
public class AppStoreServerClientTests
{
    [Fact]
    public async Task GetTransactionInfoAsync_BuildsCorrectlySignedJwt()
    {
        using var signingKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var privateKeyPem = signingKey.ExportECPrivateKeyPem();

        var options = new AppStoreServerOptions
        {
            KeyId = "TESTKEYID1",
            IssuerId = "11111111-2222-3333-4444-555555555555",
            BundleId = "com.nikolapetrovski.silafit",
            PrivateKey = privateKeyPem,
            Environment = "Sandbox"
        };

        var capturingHandler = new CapturingHandler();
        var httpClient = new HttpClient(capturingHandler);
        var sut = new AppStoreServerClient(httpClient, Options.Create(options), NullLogger<AppStoreServerClient>.Instance);

        Assert.True(sut.IsConfigured);

        await sut.GetTransactionInfoAsync("txn-123");

        Assert.NotNull(capturingHandler.CapturedAuthorizationToken);
        var handler = new JwtSecurityTokenHandler();
        var jwt = handler.ReadJwtToken(capturingHandler.CapturedAuthorizationToken);

        Assert.Equal("ES256", jwt.Header.Alg);
        Assert.Equal(options.KeyId, jwt.Header.Kid);
        Assert.Equal(options.IssuerId, jwt.Issuer);
        Assert.Equal(options.BundleId, jwt.Claims.Single(c => c.Type == "bid").Value);
        Assert.Equal("appstoreconnect-v1", jwt.Payload["aud"]);

        using var publicKey = ECDsa.Create();
        publicKey.ImportSubjectPublicKeyInfo(signingKey.ExportSubjectPublicKeyInfo(), out _);

        var validationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = options.IssuerId,
            ValidateAudience = true,
            ValidAudience = "appstoreconnect-v1",
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new ECDsaSecurityKey(publicKey),
            ValidateLifetime = true
        };

        // Throws if the signature doesn't verify against the matching public key.
        handler.ValidateToken(capturingHandler.CapturedAuthorizationToken, validationParameters, out _);
    }

    private sealed class CapturingHandler : HttpMessageHandler
    {
        public string? CapturedAuthorizationToken { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            CapturedAuthorizationToken = request.Headers.Authorization?.Parameter;
            var response = new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("{\"signedTransactionInfo\":\"\"}")
            };
            return Task.FromResult(response);
        }
    }
}
