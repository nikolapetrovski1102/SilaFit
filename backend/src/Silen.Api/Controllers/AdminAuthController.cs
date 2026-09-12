using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Common.Options;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>
/// Sign-in for the static admin dashboard (website/admin.html).
///
/// Deliberately not [Authorize]: no action here trusts a bearer token, because the
/// console's credential is an HttpOnly cookie that nginx validates before it will
/// serve the console at all (see deploy/nginx-silafit.tappit.click.conf). These
/// endpoints are their own authentication - they issue, check and revoke that
/// cookie - so an [Authorize] attribute would be guarding the wrong scheme.
///
/// Nothing here leaks anything on its own: the password step returns a challenge
/// that grants no access, and the session step only ever reports who is signed in.
/// </summary>
[ApiController]
[Route("api/admin/auth")]
public sealed class AdminAuthController(
    IAdminAuthService adminAuthService,
    IOptions<AdminAuthOptions> adminAuthOptions,
    ILogger<AdminAuthController> logger) : ControllerBase
{
    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] AdminLoginRequest request, CancellationToken cancellationToken)
    {
        var result = await adminAuthService.StartLoginAsync(request, cancellationToken);
        return result.ToActionResult(logger);
    }

    /// <summary>Second factor. Success sets the session cookie the console runs on.</summary>
    [HttpPost("verify")]
    public async Task<IActionResult> Verify([FromBody] AdminVerifyCodeRequest request, CancellationToken cancellationToken)
    {
        request.ClientIp = HttpContext.Connection.RemoteIpAddress?.ToString();

        var result = await adminAuthService.VerifyCodeAsync(request, cancellationToken);

        if (!result.IsSuccess || result.Data is null)
        {
            return result.ToActionResult(logger);
        }

        AdminSessionCookie.Write(Response, adminAuthOptions.Value, result.Data.Token, result.Data.ExpiresAtUtc);

        // The raw session token stays inside the cookie - it is never echoed into a
        // response body, so page scripts (and anything that logs bodies) can't see it.
        return new ObjectResult(ApiResponse<AdminSessionDto>.Ok(new AdminSessionDto
        {
            Username = result.Data.Username,
            ExpiresAtUtc = result.Data.ExpiresAtUtc,
            AbsoluteExpiresAtUtc = result.Data.AbsoluteExpiresAtUtc
        }))
        {
            StatusCode = result.StatusCode
        };
    }

    /// <summary>
    /// Session probe: 200 while the cookie is live, 401 once it isn't. nginx calls
    /// this as its auth_request subrequest before serving admin.html, which is why it
    /// must answer with a status code and never a redirect.
    /// </summary>
    [HttpGet("session")]
    public async Task<IActionResult> Session(CancellationToken cancellationToken)
    {
        var result = await adminAuthService.GetSessionAsync(
            AdminSessionCookie.Read(Request, adminAuthOptions.Value), cancellationToken);

        if (result.IsSuccess && result.Data is not null)
        {
            // Handy in nginx logs, and for `curl -I` while debugging a 401.
            Response.Headers[AdminSessionCookie.UsernameHeaderName] = result.Data.Username;
        }

        Response.Headers.CacheControl = "no-store";
        return result.ToActionResult(logger);
    }

    [HttpPost("logout")]
    public async Task<IActionResult> Logout(CancellationToken cancellationToken)
    {
        var result = await adminAuthService.SignOutAsync(
            AdminSessionCookie.Read(Request, adminAuthOptions.Value), cancellationToken);

        AdminSessionCookie.Clear(Response, adminAuthOptions.Value);
        return result.ToActionResult(logger);
    }

    /// <summary>Kills every session for this operator - the "I left a console open somewhere" button.</summary>
    [HttpPost("logout-all")]
    public async Task<IActionResult> LogoutAll(CancellationToken cancellationToken)
    {
        var result = await adminAuthService.SignOutEverywhereAsync(
            AdminSessionCookie.Read(Request, adminAuthOptions.Value), cancellationToken);

        AdminSessionCookie.Clear(Response, adminAuthOptions.Value);
        return result.ToActionResult(logger);
    }
}
