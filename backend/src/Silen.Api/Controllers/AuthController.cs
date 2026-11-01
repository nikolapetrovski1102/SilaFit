using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>
/// Device-id login is the app's default entry point (no account required).
/// Email/Google/Apple register or link an identity onto the caller's
/// existing Guest account when a Guest JWT is presented, upgrading it to
/// Registered tier without losing history.
/// </summary>
[ApiController]
[Route("api/auth")]
[EnableRateLimiting(RateLimitPolicies.Auth)]
public sealed class AuthController(IAuthService authService, ILogger<AuthController> logger) : ControllerBase
{
    [HttpPost("device")]
    public async Task<IActionResult> Device([FromBody] DeviceLoginRequest request, CancellationToken cancellationToken)
    {
        var result = await authService.LoginWithDeviceAsync(request.DeviceId, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("register/email/start")]
    public async Task<IActionResult> StartEmailRegistration([FromBody] EmailRegisterRequest request, CancellationToken cancellationToken)
    {
        request.ExistingUserId = User.GetUserIdOrNull();
        var result = await authService.StartEmailRegistrationAsync(request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("register/email/verify")]
    public async Task<IActionResult> VerifyEmailRegistration([FromBody] EmailVerificationRequest request, CancellationToken cancellationToken)
    {
        var result = await authService.VerifyEmailRegistrationAsync(request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("register/email/resend")]
    public async Task<IActionResult> ResendEmailVerification([FromBody] ResendEmailVerificationRequest request, CancellationToken cancellationToken)
    {
        var result = await authService.ResendEmailVerificationAsync(request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("login/email")]
    public async Task<IActionResult> LoginEmail([FromBody] EmailLoginRequest request, CancellationToken cancellationToken)
    {
        request.ExistingUserId = User.GetUserIdOrNull();
        var result = await authService.LoginEmailAsync(request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("login/google")]
    public async Task<IActionResult> LoginGoogle([FromBody] GoogleLoginRequest request, CancellationToken cancellationToken)
    {
        request.ExistingUserId = User.GetUserIdOrNull();
        var result = await authService.LoginOrLinkGoogleAsync(request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("login/apple")]
    public async Task<IActionResult> LoginApple([FromBody] AppleLoginRequest request, CancellationToken cancellationToken)
    {
        request.ExistingUserId = User.GetUserIdOrNull();
        var result = await authService.LoginOrLinkAppleAsync(request, cancellationToken);
        return result.ToActionResult(logger);
    }

    /// <summary>Trades a refresh token for a new access token. Anonymous on purpose -
    /// the access token is usually what just expired - but a still-valid bearer token
    /// is honoured so sessions from older app versions can pick up a refresh token.</summary>
    [HttpPost("refresh")]
    [EnableRateLimiting(RateLimitPolicies.SessionRefresh)]
    public async Task<IActionResult> Refresh([FromBody] RefreshSessionRequest request, CancellationToken cancellationToken)
    {
        request.CallerUserId = User.GetUserIdOrNull();
        var result = await authService.RefreshSessionAsync(request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("logout")]
    [EnableRateLimiting(RateLimitPolicies.SessionRefresh)]
    public async Task<IActionResult> Logout([FromBody] RevokeSessionRequest request, CancellationToken cancellationToken)
    {
        var result = await authService.RevokeSessionAsync(request, cancellationToken);
        return result.ToActionResult(logger);
    }
}
