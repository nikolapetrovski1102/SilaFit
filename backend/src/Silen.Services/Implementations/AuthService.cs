using Microsoft.Extensions.Options;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
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
    IOptions<JwtOptions> jwtOptions) : IAuthService
{
    public Task<ServiceResult<AuthResultDto>> LoginWithDeviceAsync(string deviceId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (string.IsNullOrWhiteSpace(deviceId))
            {
                throw new ValidationException("Device login called with an empty device id.", "A device id is required.");
            }

            var user = await authProvider.GetOrCreateDeviceUserAsync(deviceId, cancellationToken)
                ?? throw new NotFoundException($"Device login did not return a user row for device '{deviceId}'.");

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

    public Task<ServiceResult<AuthResultDto>> RegisterEmailAsync(EmailRegisterRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrWhiteSpace(request.Password))
            {
                throw new ValidationException("Email registration called with a missing email or password.", "Email and password are required.");
            }

            var existingByEmail = await authProvider.GetUserByEmailAsync(request.Email, cancellationToken);
            if (existingByEmail is not null)
            {
                throw new ConflictException($"Email '{request.Email}' is already registered.", "That email is already in use.");
            }

            var (hash, salt) = PasswordHasher.Hash(request.Password);

            var userId = await authProvider.RegisterEmailUserAsync(
                request.ExistingUserId, request.Email, hash, salt, request.DisplayName, cancellationToken);

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

    public Task<ServiceResult<AuthResultDto>> LoginEmailAsync(EmailLoginRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var user = await authProvider.GetUserByEmailAsync(request.Email, cancellationToken);

            if (user is null || user.PasswordHash is null || user.PasswordSalt is null ||
                !PasswordHasher.Verify(request.Password, user.PasswordHash, user.PasswordSalt))
            {
                throw new UnauthorizedAppException(
                    $"Email login failed for '{request.Email}'.", "Invalid email or password.");
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

            var userId = existing?.UserId ?? await authProvider.LinkExternalIdentityAsync(
                request.ExistingUserId, "Google", payload.Subject, payload.Email, payload.DisplayName, cancellationToken);

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

            var userId = existing?.UserId ?? await authProvider.LinkExternalIdentityAsync(
                request.ExistingUserId, "Apple", payload.Subject, payload.Email, request.DisplayName ?? payload.DisplayName, cancellationToken);

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
}
