using Google.Apis.Auth;
using Microsoft.Extensions.Options;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IGoogleTokenVerifier"/>
public sealed class GoogleTokenVerifier(IOptions<GoogleAuthOptions> options) : IGoogleTokenVerifier
{
    public async Task<ExternalIdentityPayload?> VerifyAsync(string idToken, CancellationToken cancellationToken = default)
    {
        var settings = new GoogleJsonWebSignature.ValidationSettings
        {
            Audience = options.Value.ClientIds
        };

        try
        {
            var payload = await GoogleJsonWebSignature.ValidateAsync(idToken, settings).ConfigureAwait(false);
            return new ExternalIdentityPayload
            {
                Subject = payload.Subject,
                Email = payload.Email,
                DisplayName = payload.Name
            };
        }
        catch (InvalidJwtException)
        {
            return null;
        }
    }
}
