using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using Silen.Common.Models;
using Silen.Common.Options;

namespace Silen.Common.Helpers;

/// <summary>
/// Builds and validates the short-lived token the password step hands back to the
/// browser while the operator types their authenticator code.
///
/// It is signed with the same Jwt:SigningKey as the app's tokens but carries a
/// distinct audience and purpose claim, which is what stops it from being usable
/// as an app bearer token (or vice versa) - the API's JwtBearer handler rejects it
/// on audience, and <see cref="ReadChallenge"/> rejects anything without the
/// purpose claim. It is deliberately stateless: a challenge proves nothing on its
/// own, so there is nothing to revoke.
/// </summary>
public static class AdminChallengeTokenFactory
{
    public const string PurposeClaimType = "purpose";
    public const string Purpose = "admin-mfa";

    private const string AudienceSuffix = ".admin-challenge";

    public static string CreateChallenge(JwtOptions options, Guid adminUserId, string username, TimeSpan lifetime)
    {
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, adminUserId.ToString()),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            new(JwtRegisteredClaimNames.UniqueName, username),
            new(PurposeClaimType, Purpose)
        };

        var signingKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(options.SigningKey));
        var credentials = new SigningCredentials(signingKey, SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: options.Issuer,
            audience: options.Audience + AudienceSuffix,
            claims: claims,
            expires: DateTime.UtcNow.Add(lifetime),
            signingCredentials: credentials);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    /// <summary>Returns null for anything that isn't a live, correctly-signed challenge.</summary>
    public static AdminChallengeModel? ReadChallenge(JwtOptions options, string? token)
    {
        if (string.IsNullOrWhiteSpace(token))
        {
            return null;
        }

        var handler = new JwtSecurityTokenHandler
        {
            // Without this, "sub" is remapped to ClaimTypes.NameIdentifier and the id read below comes back null.
            MapInboundClaims = false
        };

        var validationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = options.Issuer,
            ValidateAudience = true,
            ValidAudience = options.Audience + AudienceSuffix,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(options.SigningKey)),
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromMinutes(1)
        };

        try
        {
            var principal = handler.ValidateToken(token, validationParameters, out _);

            if (principal.FindFirstValue(PurposeClaimType) != Purpose)
            {
                return null;
            }

            var subject = principal.FindFirstValue(JwtRegisteredClaimNames.Sub);
            var username = principal.FindFirstValue(JwtRegisteredClaimNames.UniqueName);

            if (!Guid.TryParse(subject, out var adminUserId) || string.IsNullOrWhiteSpace(username))
            {
                return null;
            }

            return new AdminChallengeModel
            {
                AdminUserId = adminUserId,
                Username = username
            };
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            // Everything thrown from here is a reaction to the caller's own string -
            // a truncated JWT, an unreadable segment, a signature that isn't a
            // signature. SecurityTokenMalformedException ("JWT must have three
            // segments") is NOT a SecurityTokenException, so catching only that
            // turned a garbage cookie into a 500 with a stack trace; every one of
            // these cases means the same thing to the browser: sign in again.
            return null;
        }
    }
}
