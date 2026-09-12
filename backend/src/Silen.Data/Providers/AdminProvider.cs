using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

/// <inheritdoc cref="IAdminProvider"/>
public sealed class AdminProvider(ISqlExecutor sqlExecutor) : IAdminProvider
{
    public Task<AdminAccountModel?> GetAccountByUsernameAsync(string username, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_GetAccountByUsername",
            [SqlParameterBuilder.Create("@Username", username)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, AdminRowMapper.MapAccount, cancellationToken),
            cancellationToken);

    public Task<AdminAccountModel?> GetAccountByIdAsync(Guid adminUserId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_GetAccountById",
            [SqlParameterBuilder.Create("@AdminUserId", adminUserId)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, AdminRowMapper.MapAccount, cancellationToken),
            cancellationToken);

    public Task<Guid> UpsertAccountAsync(
        string username,
        byte[] passwordHash,
        byte[] passwordSalt,
        byte[] totpSecretCipher,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_UpsertAccount",
            [
                SqlParameterBuilder.Create("@Username", username),
                SqlParameterBuilder.Create("@PasswordHash", passwordHash),
                SqlParameterBuilder.Create("@PasswordSalt", passwordSalt),
                SqlParameterBuilder.Create("@TotpSecretCipher", totpSecretCipher)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, r => r.GetGuidValue("AdminUserId"), cancellationToken),
            cancellationToken);

    public Task<AdminLockoutStateModel?> RecordFailedLoginAsync(
        Guid adminUserId,
        int lockoutThreshold,
        int lockoutMinutes,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_RecordFailedLogin",
            [
                SqlParameterBuilder.Create("@AdminUserId", adminUserId),
                SqlParameterBuilder.Create("@LockoutThreshold", lockoutThreshold),
                SqlParameterBuilder.Create("@LockoutMinutes", lockoutMinutes)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, AdminRowMapper.MapLockoutState, cancellationToken),
            cancellationToken);

    public Task RecordSuccessfulLoginAsync(Guid adminUserId, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_Admin_RecordSuccessfulLogin",
            [SqlParameterBuilder.Create("@AdminUserId", adminUserId)],
            cancellationToken);

    public Task<Guid> CreateSessionAsync(
        Guid adminUserId,
        byte[] tokenHash,
        DateTime expiresAtUtc,
        DateTime absoluteExpiresAtUtc,
        string? createdFromIp,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_CreateSession",
            [
                SqlParameterBuilder.Create("@AdminUserId", adminUserId),
                SqlParameterBuilder.Create("@TokenHash", tokenHash),
                SqlParameterBuilder.Create("@ExpiresAtUtc", expiresAtUtc),
                SqlParameterBuilder.Create("@AbsoluteExpiresAtUtc", absoluteExpiresAtUtc),
                SqlParameterBuilder.Create("@CreatedFromIp", createdFromIp)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, r => r.GetGuidValue("AdminSessionId"), cancellationToken),
            cancellationToken);

    public Task<AdminSessionModel?> GetSessionAsync(byte[] tokenHash, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_GetSession",
            [SqlParameterBuilder.Create("@TokenHash", tokenHash)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, AdminRowMapper.MapSession, cancellationToken),
            cancellationToken);

    public Task TouchSessionAsync(Guid adminSessionId, DateTime expiresAtUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_Admin_TouchSession",
            [
                SqlParameterBuilder.Create("@AdminSessionId", adminSessionId),
                SqlParameterBuilder.Create("@ExpiresAtUtc", expiresAtUtc)
            ],
            cancellationToken);

    public Task DeleteSessionAsync(byte[] tokenHash, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_Admin_DeleteSession",
            [SqlParameterBuilder.Create("@TokenHash", tokenHash)],
            cancellationToken);

    public Task DeleteAllSessionsAsync(Guid adminUserId, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_Admin_DeleteAllSessions",
            [SqlParameterBuilder.Create("@AdminUserId", adminUserId)],
            cancellationToken);
}
