using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

/// <summary>
/// Two-factor sign-in for the static admin dashboard: password first, then the
/// authenticator code, then an opaque server-side session. Every method returns a
/// <see cref="ServiceResult{T}"/> so the controller stays a one-liner, and session
/// tokens are only ever exposed to the caller that sets the cookie.
/// </summary>
public interface IAdminAuthService
{
    /// <summary>Verifies the password and returns a short-lived challenge for the code step.</summary>
    Task<ServiceResult<AdminLoginChallengeDto>> StartLoginAsync(AdminLoginRequest request, CancellationToken cancellationToken = default);

    /// <summary>Verifies the authenticator code (or a previously emailed one) against a challenge and mints a session.</summary>
    Task<ServiceResult<AdminSessionIssuedDto>> VerifyCodeAsync(AdminVerifyCodeRequest request, CancellationToken cancellationToken = default);

    /// <summary>"Send email code instead": emails a one-time code to the operator's address on
    /// file, usable at the same <see cref="VerifyCodeAsync"/> step as their authenticator code.</summary>
    Task<ServiceResult<AdminEmailCodeSentDto>> SendEmailCodeAsync(AdminSendEmailCodeRequest request, CancellationToken cancellationToken = default);

    /// <summary>Resolves a session cookie and slides its idle deadline. This is what nginx calls via auth_request.</summary>
    Task<ServiceResult<AdminSessionDto>> GetSessionAsync(string? sessionToken, CancellationToken cancellationToken = default);

    /// <summary>Ends the current session. Idempotent - signing out twice is not an error.</summary>
    Task<ServiceResult<bool>> SignOutAsync(string? sessionToken, CancellationToken cancellationToken = default);

    /// <summary>Ends every session belonging to the signed-in operator, on all devices.</summary>
    Task<ServiceResult<bool>> SignOutEverywhereAsync(string? sessionToken, CancellationToken cancellationToken = default);
}
