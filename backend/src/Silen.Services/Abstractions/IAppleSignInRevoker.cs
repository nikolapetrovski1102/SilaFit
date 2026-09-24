namespace Silen.Services.Abstractions;

/// <summary>
/// Keeps what's needed to revoke a user's Sign in with Apple token, and
/// revokes it when their account is deleted (App Review 5.1.1(v)). Both calls
/// are best-effort: they log and return rather than fail a login or a
/// deletion over an Apple outage or missing configuration.
/// </summary>
public interface IAppleSignInRevoker
{
    /// <summary>Exchanges a login's authorization code for a refresh token and stores it on the user's Apple identity.</summary>
    Task StoreAuthorizationAsync(Guid userId, string authorizationCode, CancellationToken cancellationToken = default);

    /// <summary>Revokes the user's stored Apple refresh token, if any. Call before the account's rows are deleted.</summary>
    Task RevokeAsync(Guid userId, CancellationToken cancellationToken = default);
}
