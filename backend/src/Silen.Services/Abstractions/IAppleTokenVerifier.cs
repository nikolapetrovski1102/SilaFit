using Silen.Common.Models;

namespace Silen.Services.Abstractions;

public interface IAppleTokenVerifier
{
    /// <summary>Verifies a Sign in with Apple identity token against Apple's published JWKS. Returns null when invalid.</summary>
    Task<ExternalIdentityPayload?> VerifyAsync(string identityToken, CancellationToken cancellationToken = default);
}
