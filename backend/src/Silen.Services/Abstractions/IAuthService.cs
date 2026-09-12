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
}
