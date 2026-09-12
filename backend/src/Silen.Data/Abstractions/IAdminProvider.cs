using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>
/// Console-operator accounts and their sessions (database/schema/027_AdminAccounts.sql).
/// Separate from <see cref="IAuthProvider"/> because an admin is not an app user.
/// </summary>
public interface IAdminProvider
{
    Task<AdminAccountModel?> GetAccountByUsernameAsync(string username, CancellationToken cancellationToken = default);

    Task<AdminAccountModel?> GetAccountByIdAsync(Guid adminUserId, CancellationToken cancellationToken = default);

    /// <summary>Creates the account, or rotates the credentials of an existing username. Also clears the lockout and drops live sessions.</summary>
    Task<Guid> UpsertAccountAsync(
        string username,
        byte[] passwordHash,
        byte[] passwordSalt,
        byte[] totpSecretCipher,
        CancellationToken cancellationToken = default);

    Task<AdminLockoutStateModel?> RecordFailedLoginAsync(
        Guid adminUserId,
        int lockoutThreshold,
        int lockoutMinutes,
        CancellationToken cancellationToken = default);

    Task RecordSuccessfulLoginAsync(Guid adminUserId, CancellationToken cancellationToken = default);

    Task<Guid> CreateSessionAsync(
        Guid adminUserId,
        byte[] tokenHash,
        DateTime expiresAtUtc,
        DateTime absoluteExpiresAtUtc,
        string? createdFromIp,
        CancellationToken cancellationToken = default);

    /// <summary>Returns null when the token is unknown, expired (idle or absolute) or the account is inactive.</summary>
    Task<AdminSessionModel?> GetSessionAsync(byte[] tokenHash, CancellationToken cancellationToken = default);

    Task TouchSessionAsync(Guid adminSessionId, DateTime expiresAtUtc, CancellationToken cancellationToken = default);

    Task DeleteSessionAsync(byte[] tokenHash, CancellationToken cancellationToken = default);

    Task DeleteAllSessionsAsync(Guid adminUserId, CancellationToken cancellationToken = default);
}
