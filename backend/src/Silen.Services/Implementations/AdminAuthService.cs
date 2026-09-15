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
    IAdminRbacProvider adminRbacProvider,
    IEmailSender emailSender,
    IOptions<AdminAuthOptions> adminAuthOptions,
    IOptions<JwtOptions> jwtOptions,
    IOptions<EncryptionOptions> encryptionOptions) : IAdminAuthService
{
    /// <summary>Deliberately identical for a wrong password, an unknown username and an inactive account.</summary>
    private const string InvalidCredentialsMessage = "Invalid username or password.";

    /// <summary>How long an emailed second-factor code stays valid - same window as the
    /// registration verification email (<see cref="VerificationEmailTemplate"/>).</summary>
    private static readonly TimeSpan EmailOtpLifetime = TimeSpan.FromMinutes(10);

    /// <summary>Minimum gap between "send email code instead" requests for the same challenge.</summary>
    private static readonly TimeSpan EmailOtpResendCooldown = TimeSpan.FromSeconds(30);

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
                throw new UnauthorizedAppException($"Admin login attempted for unknown or inactive username tag {LogRedaction.Tag(request.Username)}.", InvalidCredentialsMessage);
            }

            AdminSignInThrottle.ThrowIfLocked(account, options);

            if (!PasswordHasher.Verify(request.Password, account.PasswordHash, account.PasswordSalt))
            {
                await AdminSignInThrottle.RecordFailureAsync(adminProvider, account, options, cancellationToken);
                throw new UnauthorizedAppException($"Wrong password for admin tag {LogRedaction.Tag(account.Username)}.", InvalidCredentialsMessage);
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
                throw new UnauthorizedAppException($"Admin code step for admin tag {LogRedaction.Tag(challenge.Username)} found no active account.", InvalidCredentialsMessage);
            }

            AdminSignInThrottle.ThrowIfLocked(account, options);

            var secret = AdminTotpSecretCipher.Decrypt(
                account.TotpSecretCipher,
                AdminTotpSecretCipher.ParseMasterKey(encryptionOptions.Value.MasterKeyBase64));

            var isValidTotpCode = TotpHelper.VerifyCode(secret, request.Code, DateTime.UtcNow, options.TotpDigits, options.TotpStepSeconds, options.TotpWindowSteps);
            var isValidEmailCode = !isValidTotpCode && AdminEmailOtpValidator.IsValid(account, request.Code);

            if (!isValidTotpCode && !isValidEmailCode)
            {
                await AdminSignInThrottle.RecordFailureAsync(adminProvider, account, options, cancellationToken);
                throw new UnauthorizedAppException($"Wrong authenticator/email code for admin tag {LogRedaction.Tag(account.Username)}.", "That code isn't right. Check your authenticator app (or email) and try again.");
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

            // Resolved fresh from the role, not cached anywhere - the console's
            // navigation is only ever as stale as this one lookup.
            var permissions = await adminRbacProvider.GetPermissionsAsync(account.AdminUserId, cancellationToken);

            return new AdminSessionIssuedDto
            {
                Token = token,
                Username = account.Username,
                ExpiresAtUtc = expiresAtUtc,
                AbsoluteExpiresAtUtc = absoluteExpiresAtUtc,
                RoleName = account.RoleName,
                Permissions = permissions
            };
        });

    public Task<ServiceResult<AdminEmailCodeSentDto>> SendEmailCodeAsync(AdminSendEmailCodeRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var challenge = AdminChallengeTokenFactory.ReadChallenge(jwtOptions.Value, request.ChallengeToken)
                ?? throw new UnauthorizedAppException("Admin email-code request presented an invalid or expired challenge token.", "That sign-in attempt expired. Please start again.");

            var options = adminAuthOptions.Value;
            var account = await adminProvider.GetAccountByIdAsync(challenge.AdminUserId, cancellationToken);

            if (account is null || !account.IsActive)
            {
                throw new UnauthorizedAppException($"Admin email-code request for admin tag {LogRedaction.Tag(challenge.Username)} found no active account.", InvalidCredentialsMessage);
            }

            AdminSignInThrottle.ThrowIfLocked(account, options);

            if (string.IsNullOrWhiteSpace(account.Email))
            {
                throw new ValidationException(
                    $"Admin tag {LogRedaction.Tag(account.Username)} requested an email code but has no email on file.",
                    "No email address is on file for this account. Use your authenticator app, or ask another admin to add one.");
            }

            if (account.EmailOtpLastSentAtUtc is { } lastSentAtUtc && DateTime.UtcNow - lastSentAtUtc < EmailOtpResendCooldown)
            {
                throw new ConflictException("Admin email-code requested too soon after the previous send.", "Please wait a moment before requesting another code.");
            }

            var code = VerificationCodeGenerator.GenerateCode();
            var (codeHash, codeSalt) = PasswordHasher.Hash(code);
            var expiresAtUtc = DateTime.UtcNow.Add(EmailOtpLifetime);

            await adminProvider.SetEmailOtpAsync(account.AdminUserId, account.Email, codeHash, codeSalt, expiresAtUtc, cancellationToken);

            var (subject, html) = AdminEmailOtpTemplate.Build(code);
            await emailSender.SendAsync(account.Email, subject, html, cancellationToken);

            return new AdminEmailCodeSentDto
            {
                MaskedEmail = EmailMasking.Mask(account.Email),
                ExpiresInSeconds = (int)EmailOtpLifetime.TotalSeconds
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

            // Re-read on every probe (including nginx's auth_request subrequest), so a
            // role change or revoked permission takes effect on the very next request
            // rather than whenever the session happens to be re-issued.
            var account = await adminProvider.GetAccountByIdAsync(session.AdminUserId, cancellationToken);
            var permissions = await adminRbacProvider.GetPermissionsAsync(session.AdminUserId, cancellationToken);

            return new AdminSessionDto
            {
                Username = session.Username,
                ExpiresAtUtc = expiresAtUtc > session.AbsoluteExpiresAtUtc ? session.AbsoluteExpiresAtUtc : expiresAtUtc,
                AbsoluteExpiresAtUtc = session.AbsoluteExpiresAtUtc,
                RoleName = account?.RoleName,
                Permissions = permissions
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
