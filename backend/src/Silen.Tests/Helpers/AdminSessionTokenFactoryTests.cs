using Silen.Common.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class AdminSessionTokenFactoryTests
{
    [Fact]
    public void CreateToken_IsBase64UrlEncoded32RandomBytes()
    {
        var token = AdminSessionTokenFactory.CreateToken();

        Assert.DoesNotContain('+', token);
        Assert.DoesNotContain('/', token);
        Assert.DoesNotContain('=', token);
        Assert.Equal(32, Microsoft.IdentityModel.Tokens.Base64UrlEncoder.DecodeBytes(token).Length);
    }

    [Fact]
    public void CreateToken_IsRandom_SoRepeatedCallsDiffer()
    {
        var first = AdminSessionTokenFactory.CreateToken();
        var second = AdminSessionTokenFactory.CreateToken();

        Assert.NotEqual(first, second);
    }

    [Fact]
    public void HashToken_IsDeterministic_ForTheSameToken()
    {
        var token = AdminSessionTokenFactory.CreateToken();

        Assert.Equal(AdminSessionTokenFactory.HashToken(token), AdminSessionTokenFactory.HashToken(token));
    }

    [Fact]
    public void HashToken_DifferentTokens_ProduceDifferentHashes()
    {
        var hashA = AdminSessionTokenFactory.HashToken(AdminSessionTokenFactory.CreateToken());
        var hashB = AdminSessionTokenFactory.HashToken(AdminSessionTokenFactory.CreateToken());

        Assert.NotEqual(hashA, hashB);
    }

    [Fact]
    public void HashToken_ProducesA256BitDigest()
    {
        var hash = AdminSessionTokenFactory.HashToken(AdminSessionTokenFactory.CreateToken());

        Assert.Equal(32, hash.Length);
    }
}
