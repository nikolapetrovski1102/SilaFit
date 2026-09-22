using Microsoft.Extensions.Options;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Enums;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IAuthService"/>
public sealed class AuthService(
    IAuthProvider authProvider,
    IGoogleTokenVerifier googleTokenVerifier,
    IAppleTokenVerifier appleTokenVerifier,
    IEmailSender emailSender,
    IOptions<JwtOptions> jwtOptions,
    IOptions<ReviewerBypassOptions> reviewerBypassOptions) : IAuthService
{
    /// <summary>How long an emailed code stays valid.</summary>
    private static readonly TimeSpan CodeLifetime = TimeSpan.FromMinutes(10);

    /// <summary>Minimum gap between .../resend calls for the same pending registration.</summary>
    private static readonly TimeSpan ResendCooldown = TimeSpan.FromSeconds(30);

    /// <summary>Wrong-code guesses allowed before the pending registration must be restarted.</summary>
    private const int MaxVerificationAttempts = 5;


    public Task<ServiceResult<AuthResultDto>> LoginWithDeviceAsync(string deviceId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (string.IsNullOrWhiteSpace(deviceId))
            {
                throw new ValidationException("Device login called with an empty device id.", "A device id is required.");
            }

            var user = await authProvider.GetOrCreateDeviceUserAsync(deviceId, cancellationToken)
                ?? throw new NotFoundException($"Device login did not return a user row for device tag {LogRedaction.Tag(deviceId)}.");

            var token = JwtTokenFactory.CreateToken(jwtOptions.Value, user.UserId, user.AccountTier, user.Email);

            return new AuthResultDto
            {
                Token = token,
                UserId = user.UserId,
                AccountTier = user.AccountTier.ToString(),
                Email = user.Email,
                DisplayName = user.DisplayName
            };
        });

    public Task<ServiceResult<EmailVerificationStartResultDto>> StartEmailRegistrationAsync(EmailRegisterRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrWhiteSpace(request.Password))
            {
                throw new ValidationException("Email registration called with a missing email or password.", "Email and password are required.");
            }

            var existingByEmail = await authProvider.GetUserByEmailAsync(request.Email, cancellationToken);
            if (existingByEmail is not null)
            {
                // Do not reveal that the address is already registered - a 409 here
                // is an unauthenticated account-enumeration oracle. Return the exact
                // shape a real send would, without persisting or emailing anything;
                // the synthetic id simply never verifies, so the only way to tell the
                // address exists is to try logging in with it.
                return new EmailVerificationStartResultDto
                {
                    PendingId = Guid.NewGuid(),
                    ExpiresInSeconds = (int)CodeLifetime.TotalSeconds
                };
            }

            var (passwordHash, passwordSalt) = PasswordHasher.Hash(request.Password);

            var pendingId = Guid.NewGuid();
            var isReviewerBypass = IsReviewerBypassEmail(request.Email);
            var code = isReviewerBypass ? reviewerBypassOptions.Value.Code : VerificationCodeGenerator.GenerateCode();
            var (codeHash, codeSalt) = PasswordHasher.Hash(code);
            var expiresAtUtc = DateTime.UtcNow.Add(CodeLifetime);

            await authProvider.UpsertPendingEmailVerificationAsync(
                pendingId, request.ExistingUserId, request.Email, passwordHash, passwordSalt, request.DisplayName,
                codeHash, codeSalt, expiresAtUtc, cancellationToken);

            // Reviewer account gets a fixed code and no real email - App Store / Play
            // Store reviewers don't have inbox access for the demo address.
            if (!isReviewerBypass)
            {
                var (subject, html) = VerificationEmailTemplate.Build(code);
                await emailSender.SendAsync(request.Email, subject, html, cancellationToken);
            }

            return new EmailVerificationStartResultDto
            {
                PendingId = pendingId,
                ExpiresInSeconds = (int)CodeLifetime.TotalSeconds
            };
        });

    public Task<ServiceResult<AuthResultDto>> VerifyEmailRegistrationAsync(EmailVerificationRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var pending = await authProvider.GetPendingEmailVerificationAsync(request.PendingId, cancellationToken)
                ?? throw new NotFoundException(
                    $"No pending email verification for '{request.PendingId}'.", "That verification session has expired. Please start again.");

            if (pending.ExpiresAtUtc < DateTime.UtcNow)
            {
                await authProvider.DeletePendingEmailVerificationAsync(pending.PendingId, cancellationToken);
                throw new ValidationException("Pending email verification code expired.", "That code has expired. Please request a new one.");
            }

            if (pending.AttemptCount >= MaxVerificationAttempts)
            {
                await authProvider.DeletePendingEmailVerificationAsync(pending.PendingId, cancellationToken);
                throw new UnauthorizedAppException(
                    "Pending email verification exceeded max attempts.", "Too many incorrect attempts. Please request a new code.");
            }

            if (!PasswordHasher.Verify(request.Code, pending.CodeHash, pending.CodeSalt))
            {
                await authProvider.IncrementPendingEmailVerificationAttemptAsync(pending.PendingId, cancellationToken);
                throw new ValidationException("Incorrect email verification code.", "That code isn't right. Please try again.");
            }

            var userId = await authProvider.RegisterEmailUserAsync(
                pending.ExistingUserId, pending.Email, pending.PasswordHash, pending.PasswordSalt, pending.DisplayName, cancellationToken);

            await authProvider.MarkEmailVerifiedAsync(userId, cancellationToken);
            await authProvider.DeletePendingEmailVerificationAsync(pending.PendingId, cancellationToken);

            var user = await authProvider.GetUserByIdAsync(userId, cancellationToken)
                ?? throw new NotFoundException($"User '{userId}' was registered but could not be re-read.");

            var token = JwtTokenFactory.CreateToken(jwtOptions.Value, user.UserId, user.AccountTier, user.Email);

            return new AuthResultDto
            {
                Token = token,
                UserId = user.UserId,
                AccountTier = user.AccountTier.ToString(),
                Email = user.Email,
                DisplayName = user.DisplayName
            };
        });

    public Task<ServiceResult<EmailVerificationStartResultDto>> ResendEmailVerificationAsync(ResendEmailVerificationRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var pending = await authProvider.GetPendingEmailVerificationAsync(request.PendingId, cancellationToken)
                ?? throw new NotFoundException(
                    $"No pending email verification for '{request.PendingId}'.", "That verification session has expired. Please start again.");

            if (DateTime.UtcNow - pending.LastSentAtUtc < ResendCooldown)
            {
                throw new ConflictException("Email verification resend requested too soon.", "Please wait a moment before requesting another code.");
            }

            var isReviewerBypass = IsReviewerBypassEmail(pending.Email);
            var code = isReviewerBypass ? reviewerBypassOptions.Value.Code : VerificationCodeGenerator.GenerateCode();
            var (codeHash, codeSalt) = PasswordHasher.Hash(code);
            var expiresAtUtc = DateTime.UtcNow.Add(CodeLifetime);

            await authProvider.RefreshPendingEmailVerificationAsync(pending.PendingId, codeHash, codeSalt, expiresAtUtc, cancellationToken);

            if (!isReviewerBypass)
            {
                var (subject, html) = VerificationEmailTemplate.Build(code);
                await emailSender.SendAsync(pending.Email, subject, html, cancellationToken);
            }

            return new EmailVerificationStartResultDto
            {
                PendingId = pending.PendingId,
                ExpiresInSeconds = (int)CodeLifetime.TotalSeconds
            };
        });

    /// <summary>True when both halves of the reviewer bypass are configured and match -
    /// an empty configured email/code never matches, so the bypass is off by default.</summary>
    private bool IsReviewerBypassEmail(string email)
    {
        var configuredEmail = reviewerBypassOptions.Value.Email;
        var configuredCode = reviewerBypassOptions.Value.Code;
        return !string.IsNullOrWhiteSpace(configuredEmail) && !string.IsNullOrWhiteSpace(configuredCode) &&
            string.Equals(configuredEmail, email, StringComparison.OrdinalIgnoreCase);
    }

    public Task<ServiceResult<AuthResultDto>> LoginEmailAsync(EmailLoginRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var user = await authProvider.GetUserByEmailAsync(request.Email, cancellationToken);

            if (user is null || user.PasswordHash is null || user.PasswordSalt is null ||
                !PasswordHasher.Verify(request.Password, user.PasswordHash, user.PasswordSalt))
            {
                throw new UnauthorizedAppException(
                    $"Email login failed for email tag {LogRedaction.Tag(request.Email)}.", "Invalid email or password.");
            }

            await authProvider.UpdateLastLoginAsync(user.UserId, cancellationToken);

            var token = JwtTokenFactory.CreateToken(jwtOptions.Value, user.UserId, user.AccountTier, user.Email);

            return new AuthResultDto
            {
                Token = token,
                UserId = user.UserId,
                AccountTier = user.AccountTier.ToString(),
                Email = user.Email,
                DisplayName = user.DisplayName
            };
        });

    public Task<ServiceResult<AuthResultDto>> LoginOrLinkGoogleAsync(GoogleLoginRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var payload = await googleTokenVerifier.VerifyAsync(request.IdToken, cancellationToken)
                ?? throw new UnauthorizedAppException("Google id token failed verification.", "We couldn't verify your Google sign-in.");

            var existing = await authProvider.GetIdentityAsync("Google", payload.Subject, cancellationToken);

            var linkUserId = existing is not null
                ? existing.UserId
                : await ResolveLinkTargetUserIdAsync(request.ExistingUserId, payload.Email, cancellationToken);

            var userId = existing?.UserId ?? await authProvider.LinkExternalIdentityAsync(
                linkUserId, "Google", payload.Subject, payload.Email, payload.DisplayName, cancellationToken);

            var user = await authProvider.GetUserByIdAsync(userId, cancellationToken)
                ?? throw new NotFoundException($"User '{userId}' was linked to Google but could not be re-read.");

            await authProvider.UpdateLastLoginAsync(user.UserId, cancellationToken);

            var token = JwtTokenFactory.CreateToken(jwtOptions.Value, user.UserId, user.AccountTier, user.Email);

            return new AuthResultDto
            {
                Token = token,
                UserId = user.UserId,
                AccountTier = user.AccountTier.ToString(),
                Email = user.Email,
                DisplayName = user.DisplayName
            };
        });

    public Task<ServiceResult<AuthResultDto>> LoginOrLinkAppleAsync(AppleLoginRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var payload = await appleTokenVerifier.VerifyAsync(request.IdentityToken, cancellationToken)
                ?? throw new UnauthorizedAppException("Apple identity token failed verification.", "We couldn't verify your Apple sign-in.");

            var existing = await authProvider.GetIdentityAsync("Apple", payload.Subject, cancellationToken);

            var linkUserId = existing is not null
                ? existing.UserId
                : await ResolveLinkTargetUserIdAsync(request.ExistingUserId, payload.Email, cancellationToken);

            var userId = existing?.UserId ?? await authProvider.LinkExternalIdentityAsync(
                linkUserId, "Apple", payload.Subject, payload.Email, request.DisplayName ?? payload.DisplayName, cancellationToken);

            var user = await authProvider.GetUserByIdAsync(userId, cancellationToken)
                ?? throw new NotFoundException($"User '{userId}' was linked to Apple but could not be re-read.");

            await authProvider.UpdateLastLoginAsync(user.UserId, cancellationToken);

            var token = JwtTokenFactory.CreateToken(jwtOptions.Value, user.UserId, user.AccountTier, user.Email);

            return new AuthResultDto
            {
                Token = token,
                UserId = user.UserId,
                AccountTier = user.AccountTier.ToString(),
                Email = user.Email,
                DisplayName = user.DisplayName
            };
        });

    /// <summary>
    /// Picks the account an OAuth identity should be linked to. The caller's
    /// current session (a Guest device account, in the common case, since the
    /// app is always logged in as something) may not be the account this
    /// email already belongs to - e.g. it was previously registered with a
    /// password, or linked via the other provider. Blindly stamping the
    /// email onto the current session's row would collide with UX_Users_Email
    /// and surface as a raw SQL exception, so resolve the collision here
    /// instead of leaving it to the stored procedure.
    /// </summary>
    private async Task<Guid?> ResolveLinkTargetUserIdAsync(Guid? existingUserId, string? email, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(email))
        {
            return existingUserId;
        }

        var emailOwner = await authProvider.GetUserByEmailAsync(email, cancellationToken);
        if (emailOwner is null || emailOwner.UserId == existingUserId)
        {
            return existingUserId;
        }

        if (existingUserId is null)
        {
            // No active session - sign in to the account that already owns this email.
            return emailOwner.UserId;
        }

        var currentUser = await authProvider.GetUserByIdAsync(existingUserId.Value, cancellationToken);
        if (currentUser is null || currentUser.AccountTier == AccountTier.Guest)
        {
            // The current session is just an unclaimed device shell - sign in to
            // the existing account instead of colliding with it.
            return emailOwner.UserId;
        }

        // The current session is itself a distinct registered account - merging
        // it into another real account's data silently would be surprising and
        // destructive, so surface a clear, actionable conflict instead.
        throw new ConflictException(
            $"OAuth login email tag {LogRedaction.Tag(email)} belongs to a different account than the current session.",
            "An account already exists with this email. Sign in with its original method, then link this provider from Settings.");
    }
}
