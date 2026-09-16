using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using Silen.Common.Models;
using Silen.Common.Options;

namespace Silen.Common.Helpers;

/// <summary>
/// Builds and validates the link an operator clicks in their operator-creation
/// confirmation email to prove they control the address on file.
///
/// Same shape as <see cref="AdminChallengeTokenFactory"/> - signed with the app's
/// Jwt:SigningKey under a distinct audience/purpose so it can never be presented
/// as a bearer token or an MFA challenge (or vice versa) - and deliberately
/// stateless, so confirming needs no extra table or column beyond
/// AdminUsers.EmailConfirmedAtUtc itself. The email is carried as a claim and
/// re-checked against the row at confirm time, so a link from before the address
/// was changed can never confirm the new one.
/// </summary>
public static class AdminEmailConfirmTokenFactory
{
    public const string PurposeClaimType = "purpose";
    public const string Purpose = "admin-email-confirm";

    private const string EmailClaimType = "email";
    private const string AudienceSuffix = ".admin-email-confirm";

    public static string CreateToken(JwtOptions options, Guid adminUserId, string email, TimeSpan lifetime)
    {
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, adminUserId.ToString()),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            new(EmailClaimType, email),
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

    /// <summary>Returns null for anything that isn't a live, correctly-signed confirmation token.</summary>
    public static AdminEmailConfirmModel? ReadToken(JwtOptions options, string? token)
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
            var email = principal.FindFirstValue(EmailClaimType);

            if (!Guid.TryParse(subject, out var adminUserId) || string.IsNullOrWhiteSpace(email))
            {
                return null;
            }

            return new AdminEmailConfirmModel
            {
                AdminUserId = adminUserId,
                Email = email
            };
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            // Same reasoning as AdminChallengeTokenFactory: every failure mode here
            // means the same thing to the caller - the link is no good, ask for a new one.
            return null;
        }
    }
}
