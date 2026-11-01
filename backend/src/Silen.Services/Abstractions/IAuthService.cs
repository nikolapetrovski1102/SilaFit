using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

public interface IAuthService
{
    Task<ServiceResult<AuthResultDto>> LoginWithDeviceAsync(string deviceId, CancellationToken cancellationToken = default);

    /// <summary>Step 1 of email registration: validates the email is free, stashes the
    /// pending registration, and emails a 6-digit code. No account exists yet.</summary>
    Task<ServiceResult<EmailVerificationStartResultDto>> StartEmailRegistrationAsync(EmailRegisterRequest request, CancellationToken cancellationToken = default);

    /// <summary>Step 2: confirms the emailed code and only then creates (or upgrades) the account.</summary>
    Task<ServiceResult<AuthResultDto>> VerifyEmailRegistrationAsync(EmailVerificationRequest request, CancellationToken cancellationToken = default);

    /// <summary>Re-sends a fresh code for an already-started pending registration.</summary>
    Task<ServiceResult<EmailVerificationStartResultDto>> ResendEmailVerificationAsync(ResendEmailVerificationRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<AuthResultDto>> LoginEmailAsync(EmailLoginRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<AuthResultDto>> LoginOrLinkGoogleAsync(GoogleLoginRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<AuthResultDto>> LoginOrLinkAppleAsync(AppleLoginRequest request, CancellationToken cancellationToken = default);

    /// <summary>Trades a refresh token for a new access token (same refresh token back, expiry
    /// slid forward). With no refresh token, a caller holding a still-valid access token -
    /// a session from before refresh tokens existed - gets its first pair instead.</summary>
    Task<ServiceResult<AuthResultDto>> RefreshSessionAsync(RefreshSessionRequest request, CancellationToken cancellationToken = default);

    /// <summary>Sign-out: the refresh token can't mint another access token.</summary>
    Task<ServiceResult<bool>> RevokeSessionAsync(RevokeSessionRequest request, CancellationToken cancellationToken = default);
}
