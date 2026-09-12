using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

/// <inheritdoc cref="IAuthProvider"/>
public sealed class AuthProvider(ISqlExecutor sqlExecutor) : IAuthProvider
{
    public Task<UserAccountModel?> GetOrCreateDeviceUserAsync(string deviceId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Auth_GetOrCreateDeviceUser",
            [SqlParameterBuilder.Create("@DeviceId", deviceId)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, AuthRowMapper.MapAccount, cancellationToken),
            cancellationToken);

    public Task<UserAccountModel?> GetUserByEmailAsync(string email, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Auth_GetUserByEmail",
            [SqlParameterBuilder.Create("@Email", email)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, AuthRowMapper.MapAccountWithCredentials, cancellationToken),
            cancellationToken);

    public Task<UserAccountModel?> GetUserByIdAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Auth_GetUserById",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, AuthRowMapper.MapAccount, cancellationToken),
            cancellationToken);

    public Task<UserAccountModel?> GetIdentityAsync(string provider, string externalId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Auth_GetIdentity",
            [SqlParameterBuilder.Create("@Provider", provider), SqlParameterBuilder.Create("@ExternalId", externalId)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, AuthRowMapper.MapAccount, cancellationToken),
            cancellationToken);

    public Task<Guid> RegisterEmailUserAsync(
        Guid? existingUserId,
        string email,
        byte[] passwordHash,
        byte[] passwordSalt,
        string? displayName,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Auth_RegisterEmailUser",
            [
                SqlParameterBuilder.Create("@UserId", existingUserId),
                SqlParameterBuilder.Create("@Email", email),
                SqlParameterBuilder.Create("@PasswordHash", passwordHash),
                SqlParameterBuilder.Create("@PasswordSalt", passwordSalt),
                SqlParameterBuilder.Create("@DisplayName", displayName)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, r => r.GetGuidValue("UserId"), cancellationToken),
            cancellationToken);

    public Task<Guid> LinkExternalIdentityAsync(
        Guid? existingUserId,
        string provider,
        string externalId,
        string? email,
        string? displayName,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Auth_LinkExternalIdentity",
            [
                SqlParameterBuilder.Create("@UserId", existingUserId),
                SqlParameterBuilder.Create("@Provider", provider),
                SqlParameterBuilder.Create("@ExternalId", externalId),
                SqlParameterBuilder.Create("@Email", email),
                SqlParameterBuilder.Create("@DisplayName", displayName)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, r => r.GetGuidValue("UserId"), cancellationToken),
            cancellationToken);

    public Task UpdateLastLoginAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_Auth_UpdateLastLogin",
            [SqlParameterBuilder.Create("@UserId", userId)],
            cancellationToken);

    public Task UpsertPendingEmailVerificationAsync(
        Guid pendingId,
        Guid? existingUserId,
        string email,
        byte[] passwordHash,
        byte[] passwordSalt,
        string? displayName,
        byte[] codeHash,
        byte[] codeSalt,
        DateTime expiresAtUtc,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_Auth_UpsertPendingEmailVerification",
            [
                SqlParameterBuilder.Create("@PendingId", pendingId),
                SqlParameterBuilder.Create("@ExistingUserId", existingUserId),
                SqlParameterBuilder.Create("@Email", email),
                SqlParameterBuilder.Create("@PasswordHash", passwordHash),
                SqlParameterBuilder.Create("@PasswordSalt", passwordSalt),
                SqlParameterBuilder.Create("@DisplayName", displayName),
                SqlParameterBuilder.Create("@CodeHash", codeHash),
                SqlParameterBuilder.Create("@CodeSalt", codeSalt),
                SqlParameterBuilder.Create("@ExpiresAtUtc", expiresAtUtc)
            ],
            cancellationToken);

    public Task<PendingEmailVerificationModel?> GetPendingEmailVerificationAsync(Guid pendingId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Auth_GetPendingEmailVerification",
            [SqlParameterBuilder.Create("@PendingId", pendingId)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, AuthRowMapper.MapPendingVerification, cancellationToken),
            cancellationToken);

    public Task IncrementPendingEmailVerificationAttemptAsync(Guid pendingId, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_Auth_IncrementPendingEmailVerificationAttempt",
            [SqlParameterBuilder.Create("@PendingId", pendingId)],
            cancellationToken);

    public Task RefreshPendingEmailVerificationAsync(
        Guid pendingId, byte[] codeHash, byte[] codeSalt, DateTime expiresAtUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_Auth_RefreshPendingEmailVerification",
            [
                SqlParameterBuilder.Create("@PendingId", pendingId),
                SqlParameterBuilder.Create("@CodeHash", codeHash),
                SqlParameterBuilder.Create("@CodeSalt", codeSalt),
                SqlParameterBuilder.Create("@ExpiresAtUtc", expiresAtUtc)
            ],
            cancellationToken);

    public Task DeletePendingEmailVerificationAsync(Guid pendingId, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_Auth_DeletePendingEmailVerification",
            [SqlParameterBuilder.Create("@PendingId", pendingId)],
            cancellationToken);

    public Task MarkEmailVerifiedAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_Auth_MarkEmailVerified",
            [SqlParameterBuilder.Create("@UserId", userId)],
            cancellationToken);
}
