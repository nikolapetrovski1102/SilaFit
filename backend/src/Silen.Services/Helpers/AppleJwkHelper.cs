using Microsoft.IdentityModel.Tokens;

namespace Silen.Services.Helpers;

/// <summary>
/// Outside helper that fetches Apple's published JSON Web Key Set and
/// resolves the RSA signing key matching a token's "kid" header, so
/// AppleTokenVerifier itself stays free of private methods.
/// </summary>
public static class AppleJwkHelper
{
    private const string AppleJwksUrl = "https://appleid.apple.com/auth/keys";

    public static async Task<SecurityKey?> ResolveSigningKeyAsync(HttpClient httpClient, string kid, CancellationToken cancellationToken)
    {
        var json = await httpClient.GetStringAsync(AppleJwksUrl, cancellationToken).ConfigureAwait(false);
        var keySet = new JsonWebKeySet(json);

        var matchingKey = keySet.Keys.FirstOrDefault(k => k.Kid == kid);
        if (matchingKey is null || !JsonWebKeyConverter.TryConvertToSecurityKey(matchingKey, out var securityKey))
        {
            return null;
        }

        return securityKey;
    }
}
