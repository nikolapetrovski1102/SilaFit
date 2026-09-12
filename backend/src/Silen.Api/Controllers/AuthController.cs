using Microsoft.AspNetCore.Mvc;
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
}
