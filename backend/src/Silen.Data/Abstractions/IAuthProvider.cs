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
}
