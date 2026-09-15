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

    /// <summary>Creates the account, or rotates the credentials of an existing username. Also clears the lockout and drops live sessions.
    /// A null <paramref name="email"/> leaves any existing address alone; pass an empty string to clear it.</summary>
    Task<Guid> UpsertAccountAsync(
        string username,
        byte[] passwordHash,
        byte[] passwordSalt,
        byte[] totpSecretCipher,
        string? email = null,
        CancellationToken cancellationToken = default);

    /// <summary>Sets or clears the recovery email without touching credentials or sessions.</summary>
    Task SetEmailAsync(Guid adminUserId, string? email, CancellationToken cancellationToken = default);

    /// <summary>
    /// Records the "send email code instead" code just emailed to <paramref name="email"/>.
    /// A no-op (zero rows affected) if that address no longer matches the account's Email -
    /// the caller re-reads the account and reports "no email on file" instead.
    /// </summary>
    Task SetEmailOtpAsync(
        Guid adminUserId,
        string email,
        byte[] codeHash,
        byte[] codeSalt,
        DateTime expiresAtUtc,
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
