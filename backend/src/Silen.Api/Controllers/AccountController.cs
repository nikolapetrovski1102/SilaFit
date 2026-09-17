using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>
/// Self-service account deletion (Apple App Store Review Guideline 5.1.1(v) /
/// Google Play data-safety requirement) and full "download my data" export.
/// </summary>
[ApiController]
[Route("api/account")]
[Authorize]
public sealed class AccountController(IAccountService accountService, ILogger<AccountController> logger) : ControllerBase
{
    /// <summary>Emails the export to the account's address rather than returning it in
    /// the response - POST, not GET, since it has that side effect.</summary>
    [HttpPost("export")]
    public async Task<IActionResult> Export(CancellationToken cancellationToken)
    {
        var result = await accountService.ExportAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpDelete]
    public async Task<IActionResult> Delete(CancellationToken cancellationToken)
    {
        var result = await accountService.DeleteAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }
}
