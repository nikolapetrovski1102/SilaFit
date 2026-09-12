using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using Silen.Common.Enums;
using Silen.Common.Options;

namespace Silen.Common.Helpers;

/// <summary>
/// Static helper that issues signed JWTs carrying the claims the API's
/// authorization policies rely on (subject, account tier, email). Shared by
/// every login/register/link flow instead of duplicating token-building
/// logic in each service.
/// </summary>
public static class JwtTokenFactory
{
    public const string TierClaimType = "tier";

    public static string CreateToken(JwtOptions options, Guid userId, AccountTier tier, string? email)
    {
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, userId.ToString()),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            new(TierClaimType, tier.ToString())
        };

        if (!string.IsNullOrWhiteSpace(email))
        {
            claims.Add(new Claim(JwtRegisteredClaimNames.Email, email));
        }

        var signingKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(options.SigningKey));
        var credentials = new SigningCredentials(signingKey, SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: options.Issuer,
            audience: options.Audience,
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(options.ExpiryMinutes),
            signingCredentials: credentials);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
