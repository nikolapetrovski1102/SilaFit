using Silen.Common.Enums;
using Silen.Common.Helpers;
using Silen.Common.Options;
using Xunit;

namespace Silen.Tests.Helpers;

public class AdminChallengeTokenFactoryTests
{
    private static JwtOptions Options() => new()
    {
        Issuer = "silen-tests",
        Audience = "silen-admin",
        SigningKey = "unit-test-signing-key-at-least-256-bits-long!!",
        ExpiryMinutes = 60
    };

    [Fact]
    public void CreateChallenge_ReadChallenge_RoundTripsTheAdminIdentity()
    {
        var options = Options();
        var adminUserId = Guid.NewGuid();

        var token = AdminChallengeTokenFactory.CreateChallenge(options, adminUserId, "ops-admin", TimeSpan.FromMinutes(5));
        var challenge = AdminChallengeTokenFactory.ReadChallenge(options, token);

        Assert.NotNull(challenge);
        Assert.Equal(adminUserId, challenge.AdminUserId);
        Assert.Equal("ops-admin", challenge.Username);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("not-a-jwt-at-all")]
    public void ReadChallenge_MissingOrGarbageToken_ReturnsNullRatherThanThrowing(string? token)
    {
        Assert.Null(AdminChallengeTokenFactory.ReadChallenge(Options(), token));
    }

    [Fact]
    public void ReadChallenge_ExpiredChallenge_ReturnsNull()
    {
        var options = Options();

        var token = AdminChallengeTokenFactory.CreateChallenge(options, Guid.NewGuid(), "ops-admin", TimeSpan.FromMinutes(-5));

        Assert.Null(AdminChallengeTokenFactory.ReadChallenge(options, token));
    }

    [Fact]
    public void ReadChallenge_RejectsATokenSignedWithADifferentKey()
    {
        var options = Options();
        var token = AdminChallengeTokenFactory.CreateChallenge(options, Guid.NewGuid(), "ops-admin", TimeSpan.FromMinutes(5));

        var wrongKeyOptions = Options();
        wrongKeyOptions.SigningKey = "a-completely-different-signing-key-256-bits!!";

        Assert.Null(AdminChallengeTokenFactory.ReadChallenge(wrongKeyOptions, token));
    }

    [Fact]
    public void ReadChallenge_RejectsARegularAppBearerToken_BecauseAudienceAndPurposeDiffer()
    {
        var options = Options();
        // Same signing key/issuer as an app token would use, but minted by
        // JwtTokenFactory with the app's own audience and no purpose claim -
        // exactly the confusion this separate audience/purpose is meant to stop.
        var appToken = JwtTokenFactory.CreateToken(options, Guid.NewGuid(), AccountTier.Registered, "admin@example.com");

        Assert.Null(AdminChallengeTokenFactory.ReadChallenge(options, appToken));
    }
}
