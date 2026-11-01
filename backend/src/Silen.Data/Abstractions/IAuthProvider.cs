using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IAuthProvider
{
    Task<UserAccountModel?> GetOrCreateDeviceUserAsync(string deviceId, CancellationToken cancellationToken = default);

    Task<UserAccountModel?> GetUserByEmailAsync(string email, CancellationToken cancellationToken = default);

    Task<UserAccountModel?> GetUserByIdAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<UserAccountModel?> GetIdentityAsync(string provider, string externalId, CancellationToken cancellationToken = default);

    Task<Guid> RegisterEmailUserAsync(
        Guid? existingUserId,
        string email,
        byte[] passwordHash,
        byte[] passwordSalt,
        string? displayName,
        CancellationToken cancellationToken = default);

    Task<Guid> LinkExternalIdentityAsync(
        Guid? existingUserId,
        string provider,
        string externalId,
        string? email,
        string? displayName,
        CancellationToken cancellationToken = default);

    Task UpdateLastLoginAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Makes device login on <paramref name="deviceUserId"/>'s device answer with
    /// <paramref name="accountUserId"/>. No-op unless the device user is a Guest.
    /// </summary>
    Task LinkDeviceToAccountAsync(Guid deviceUserId, Guid accountUserId, CancellationToken cancellationToken = default);

    /// <summary>Stores a refresh token's hash for <paramref name="userId"/>, pruning that user's expired and oldest tokens.</summary>
    Task CreateRefreshTokenAsync(Guid userId, byte[] tokenHash, DateTime expiresAtUtc, CancellationToken cancellationToken = default);

    /// <summary>Redeems a refresh token, sliding its expiry to <paramref name="expiresAtUtc"/>. Null when the
    /// token is unknown, expired or revoked, or its account is inactive.</summary>
    Task<UserAccountModel?> UseRefreshTokenAsync(byte[] tokenHash, DateTime expiresAtUtc, CancellationToken cancellationToken = default);

    Task RevokeRefreshTokenAsync(byte[] tokenHash, CancellationToken cancellationToken = default);

    Task UpsertPendingEmailVerificationAsync(
        Guid pendingId,
        Guid? existingUserId,
        string email,
        byte[] passwordHash,
        byte[] passwordSalt,
        string? displayName,
        byte[] codeHash,
        byte[] codeSalt,
        DateTime expiresAtUtc,
        CancellationToken cancellationToken = default);

    Task<PendingEmailVerificationModel?> GetPendingEmailVerificationAsync(Guid pendingId, CancellationToken cancellationToken = default);

    Task IncrementPendingEmailVerificationAttemptAsync(Guid pendingId, CancellationToken cancellationToken = default);

    Task RefreshPendingEmailVerificationAsync(
        Guid pendingId, byte[] codeHash, byte[] codeSalt, DateTime expiresAtUtc, CancellationToken cancellationToken = default);

    Task DeletePendingEmailVerificationAsync(Guid pendingId, CancellationToken cancellationToken = default);

    Task MarkEmailVerifiedAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>True when the account has no password and no sign-in identity at all - a
    /// partner-provisioned account its owner hasn't signed in to yet.</summary>
    Task<bool> IsUnclaimedAccountAsync(Guid userId, CancellationToken cancellationToken = default);
}
