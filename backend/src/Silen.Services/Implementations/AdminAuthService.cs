using Microsoft.Extensions.Options;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IAdminAuthService"/>
public sealed class AdminAuthService(
    IAdminProvider adminProvider,
    IOptions<AdminAuthOptions> adminAuthOptions,
    IOptions<JwtOptions> jwtOptions,
    IOptions<EncryptionOptions> encryptionOptions) : IAdminAuthService
{
    /// <summary>Deliberately identical for a wrong password, an unknown username and an inactive account.</summary>
    private const string InvalidCredentialsMessage = "Invalid username or password.";

    /// <summary>Burns a PBKDF2 cycle for unknown usernames too, so response time doesn't reveal who exists.</summary>
    private static readonly Lazy<(byte[] Hash, byte[] Salt)> DecoyCredentials =
        new(() => PasswordHasher.Hash("decoy-password-never-used"));

    public Task<ServiceResult<AdminLoginChallengeDto>> StartLoginAsync(AdminLoginRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (string.IsNullOrWhiteSpace(request.Username) || string.IsNullOrWhiteSpace(request.Password))
            {
                throw new ValidationException("Admin login called with a missing username or password.", "Username and password are required.");
            }

            var options = adminAuthOptions.Value;
            var account = await adminProvider.GetAccountByUsernameAsync(request.Username.Trim(), cancellationToken);

            if (account is null || !account.IsActive)
            {
                PasswordHasher.Verify(request.Password, DecoyCredentials.Value.Hash, DecoyCredentials.Value.Salt);
                throw new UnauthorizedAppException($"Admin login attempted for unknown or inactive username '{request.Username}'.", InvalidCredentialsMessage);
            }

            AdminSignInThrottle.ThrowIfLocked(account, options);

            if (!PasswordHasher.Verify(request.Password, account.PasswordHash, account.PasswordSalt))
            {
                await AdminSignInThrottle.RecordFailureAsync(adminProvider, account, options, cancellationToken);
                throw new UnauthorizedAppException($"Wrong password for admin '{account.Username}'.", InvalidCredentialsMessage);
            }

            var lifetime = TimeSpan.FromMinutes(options.ChallengeMinutes);

            return new AdminLoginChallengeDto
            {
                ChallengeToken = AdminChallengeTokenFactory.CreateChallenge(jwtOptions.Value, account.AdminUserId, account.Username, lifetime),
                ExpiresInSeconds = (int)lifetime.TotalSeconds
            };
        });

    public Task<ServiceResult<AdminSessionIssuedDto>> VerifyCodeAsync(AdminVerifyCodeRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var challenge = AdminChallengeTokenFactory.ReadChallenge(jwtOptions.Value, request.ChallengeToken)
                ?? throw new UnauthorizedAppException("Admin code step presented an invalid or expired challenge token.", "That sign-in attempt expired. Please start again.");

            var options = adminAuthOptions.Value;
            var account = await adminProvider.GetAccountByIdAsync(challenge.AdminUserId, cancellationToken);

            if (account is null || !account.IsActive)
            {
                throw new UnauthorizedAppException($"Admin code step for '{challenge.Username}' found no active account.", InvalidCredentialsMessage);
            }

            AdminSignInThrottle.ThrowIfLocked(account, options);

            var secret = AdminTotpSecretCipher.Decrypt(
                account.TotpSecretCipher,
                AdminTotpSecretCipher.ParseMasterKey(encryptionOptions.Value.MasterKeyBase64));

            if (!TotpHelper.VerifyCode(secret, request.Code, DateTime.UtcNow, options.TotpDigits, options.TotpStepSeconds, options.TotpWindowSteps))
            {
                await AdminSignInThrottle.RecordFailureAsync(adminProvider, account, options, cancellationToken);
                throw new UnauthorizedAppException($"Wrong authenticator code for admin '{account.Username}'.", "That code isn't right. Check your authenticator app and try again.");
            }

            await adminProvider.RecordSuccessfulLoginAsync(account.AdminUserId, cancellationToken);

            var token = AdminSessionTokenFactory.CreateToken();
            var now = DateTime.UtcNow;
            var expiresAtUtc = now.AddMinutes(options.SessionIdleMinutes);
            var absoluteExpiresAtUtc = now.AddMinutes(options.SessionAbsoluteMinutes);

            await adminProvider.CreateSessionAsync(
                account.AdminUserId,
                AdminSessionTokenFactory.HashToken(token),
                expiresAtUtc,
                absoluteExpiresAtUtc,
                request.ClientIp,
                cancellationToken);

            return new AdminSessionIssuedDto
            {
                Token = token,
                Username = account.Username,
                ExpiresAtUtc = expiresAtUtc,
                AbsoluteExpiresAtUtc = absoluteExpiresAtUtc
            };
        });

    public Task<ServiceResult<AdminSessionDto>> GetSessionAsync(string? sessionToken, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var session = await AdminSessionResolver.ResolveOrThrowAsync(adminProvider, sessionToken, cancellationToken);

            // Sliding idle window: every authenticated request (including nginx's
            // subrequest) pushes the deadline out, but never past the absolute cap -
            // usp_Admin_TouchSession clamps it server-side.
            var options = adminAuthOptions.Value;
            var expiresAtUtc = DateTime.UtcNow.AddMinutes(options.SessionIdleMinutes);
            await adminProvider.TouchSessionAsync(session.AdminSessionId, expiresAtUtc, cancellationToken);

            return new AdminSessionDto
            {
                Username = session.Username,
                ExpiresAtUtc = expiresAtUtc > session.AbsoluteExpiresAtUtc ? session.AbsoluteExpiresAtUtc : expiresAtUtc,
                AbsoluteExpiresAtUtc = session.AbsoluteExpiresAtUtc
            };
        });

    public Task<ServiceResult<bool>> SignOutAsync(string? sessionToken, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (!string.IsNullOrWhiteSpace(sessionToken))
            {
                await adminProvider.DeleteSessionAsync(AdminSessionTokenFactory.HashToken(sessionToken), cancellationToken);
            }

            return true;
        });

    public Task<ServiceResult<bool>> SignOutEverywhereAsync(string? sessionToken, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var session = await AdminSessionResolver.ResolveOrThrowAsync(adminProvider, sessionToken, cancellationToken);
            await adminProvider.DeleteAllSessionsAsync(session.AdminUserId, cancellationToken);
            return true;
        });
}
