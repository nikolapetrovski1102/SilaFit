using Silen.Common.Models;

namespace Silen.Services.Abstractions;

public interface IGoogleTokenVerifier
{
    /// <summary>Verifies a Google Sign-In ID token's signature, issuer and audience. Returns null when invalid.</summary>
    Task<ExternalIdentityPayload?> VerifyAsync(string idToken, CancellationToken cancellationToken = default);
}
