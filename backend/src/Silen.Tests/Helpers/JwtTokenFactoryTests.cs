using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.IdentityModel.Tokens;
using Silen.Common.Enums;
using Silen.Common.Helpers;
using Silen.Common.Options;
using Xunit;

namespace Silen.Tests.Helpers;

public class JwtTokenFactoryTests
{
    private static JwtOptions Options() => new()
    {
        Issuer = "silen-tests",
        Audience = "silen-app",
        SigningKey = "unit-test-signing-key-at-least-256-bits-long!!",
        ExpiryMinutes = 60
    };

    [Fact]
    public void CreateToken_CarriesSubjectTierAndEmailClaims()
    {
        var options = Options();
        var userId = Guid.NewGuid();

        var token = JwtTokenFactory.CreateToken(options, userId, AccountTier.Registered, "user@example.com");

        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);
        Assert.Equal(userId.ToString(), jwt.Subject);
        Assert.Equal(options.Issuer, jwt.Issuer);
        Assert.Contains(options.Audience, jwt.Audiences);
        Assert.Equal(nameof(AccountTier.Registered), jwt.Claims.Single(c => c.Type == JwtTokenFactory.TierClaimType).Value);
        Assert.Equal("user@example.com", jwt.Claims.Single(c => c.Type == JwtRegisteredClaimNames.Email).Value);
    }

    [Fact]
    public void CreateToken_NullEmail_OmitsEmailClaim_ForGuestAccounts()
    {
        var options = Options();

        var token = JwtTokenFactory.CreateToken(options, Guid.NewGuid(), AccountTier.Guest, email: null);

        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);
        Assert.DoesNotContain(jwt.Claims, c => c.Type == JwtRegisteredClaimNames.Email);
        Assert.Equal(nameof(AccountTier.Guest), jwt.Claims.Single(c => c.Type == JwtTokenFactory.TierClaimType).Value);
    }

    [Fact]
    public void CreateToken_ExpiresApproximatelyExpiryMinutesFromNow()
    {
        var options = Options();

        var token = JwtTokenFactory.CreateToken(options, Guid.NewGuid(), AccountTier.Registered, null);

        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);
        var expectedExpiry = DateTime.UtcNow.AddMinutes(options.ExpiryMinutes);
        Assert.True(Math.Abs((jwt.ValidTo - expectedExpiry).TotalSeconds) < 5);
    }

    [Fact]
    public void CreateToken_ValidatesAgainstItsOwnSigningKey()
    {
        var options = Options();
        var userId = Guid.NewGuid();
        var token = JwtTokenFactory.CreateToken(options, userId, AccountTier.Registered, "user@example.com");

        var handler = new JwtSecurityTokenHandler { MapInboundClaims = false };
        var principal = handler.ValidateToken(token, new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = options.Issuer,
            ValidateAudience = true,
            ValidAudience = options.Audience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(System.Text.Encoding.UTF8.GetBytes(options.SigningKey))
        }, out _);

        Assert.Equal(userId.ToString(), principal.FindFirstValue(JwtRegisteredClaimNames.Sub));
    }
}
