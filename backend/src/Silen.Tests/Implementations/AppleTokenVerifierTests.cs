using Microsoft.Extensions.Options;
using Silen.Common.Options;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

// Only the one branch of AppleTokenVerifier that never touches the network is covered here:
// JwtSecurityTokenHandler.CanReadToken(...) short-circuits before any call to Apple's JWKS
// endpoint, so a garbage/unreadable identity token can be exercised with a real (unused)
// HttpClient and no mocking. Every other branch (signature validation against Apple's live
// JWKS via AppleJwkHelper.ResolveSigningKeyAsync) needs a real or extensively-mocked HTTP
// round trip to exercise meaningfully, so per scope it is intentionally left untested here.
public class AppleTokenVerifierTests
{
    private readonly AppleTokenVerifier sut = new(new HttpClient(), Options.Create(new AppleAuthOptions { ClientIds = ["com.silen.app"] }));

    [Theory]
    [InlineData("not-a-jwt-at-all")]
    [InlineData("")]
    public async Task VerifyAsync_UnreadableToken_ReturnsNull_WithoutAnyNetworkCall(string identityToken)
    {
        var result = await sut.VerifyAsync(identityToken);

        Assert.Null(result);
    }
}
