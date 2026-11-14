using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Silen.Common.Helpers;
using Silen.Common.Options;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>
/// The console's download-links report: page opens per tagged link, and the installs,
/// sign-ups and purchases credited to them. Same cookie-session shape as
/// <see cref="AdminContentController"/>; the service requires users.read.
/// </summary>
[ApiController]
[Route("api/admin/download-links")]
public sealed class AdminDownloadLinksController(
    IDownloadLinkService downloadLinkService,
    IOptions<AdminAuthOptions> adminAuthOptions,
    ILogger<AdminDownloadLinksController> logger) : ControllerBase
{
    /// <summary><c>days</c> = the reported period ending today; 0 or missing = all time.</summary>
    [HttpGet]
    public async Task<IActionResult> GetReport([FromQuery] int days, CancellationToken cancellationToken) =>
        (await downloadLinkService.GetReportAsync(
            AdminSessionCookie.Read(Request, adminAuthOptions.Value), days, cancellationToken)).ToActionResult(logger);
}
