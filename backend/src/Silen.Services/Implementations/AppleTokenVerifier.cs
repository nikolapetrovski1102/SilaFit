using System.IdentityModel.Tokens.Jwt;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IAppleTokenVerifier"/>
public sealed class AppleTokenVerifier(HttpClient httpClient, IOptions<AppleAuthOptions> options) : IAppleTokenVerifier
{
    private const string AppleIssuer = "https://appleid.apple.com";

    public async Task<ExternalIdentityPayload?> VerifyAsync(string identityToken, CancellationToken cancellationToken = default)
    {
        // Without this, ValidateToken remaps "sub"/"email" to legacy ClaimTypes URIs,
        // so the JwtRegisteredClaimNames lookups below would always miss and every
        // otherwise-valid Apple token would be rejected.
        var handler = new JwtSecurityTokenHandler { MapInboundClaims = false };
        if (!handler.CanReadToken(identityToken))
        {
            return null;
        }

        var kid = handler.ReadJwtToken(identityToken).Header.Kid;
        var signingKey = await AppleJwkHelper.ResolveSigningKeyAsync(httpClient, kid, cancellationToken).ConfigureAwait(false);
        if (signingKey is null)
        {
            return null;
        }

        var validationParameters = new TokenValidationParameters
        {
            ValidIssuer = AppleIssuer,
            ValidAudiences = options.Value.ClientIds,
            IssuerSigningKey = signingKey,
            ValidateLifetime = true
        };

        try
        {
            var principal = handler.ValidateToken(identityToken, validationParameters, out _);
            var subject = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
            if (string.IsNullOrEmpty(subject))
            {
                return null;
            }

            return new ExternalIdentityPayload
            {
                Subject = subject,
                Email = principal.FindFirst(JwtRegisteredClaimNames.Email)?.Value
            };
        }
        catch (SecurityTokenException)
        {
            return null;
        }
    }
}
