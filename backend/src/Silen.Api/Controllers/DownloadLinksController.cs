using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>The beacon website/js/download.js sends on every open of the download page
/// (https://sila.fitness/download?src=...). Anonymous: the visitor has no account yet.</summary>
[ApiController]
[Route("api/download")]
[AllowAnonymous]
[EnableRateLimiting(RateLimitPolicies.DownloadVisit)]
public sealed class DownloadLinksController(IDownloadLinkService downloadLinkService, ILogger<DownloadLinksController> logger) : ControllerBase
{
    [HttpPost("visit")]
    public async Task<IActionResult> Visit([FromBody] DownloadVisitRequest request, CancellationToken cancellationToken)
    {
        var result = await downloadLinkService.RecordVisitAsync(
            request, HttpContext.Connection.RemoteIpAddress, Request.Headers.UserAgent.ToString(), cancellationToken);
        return result.ToActionResult(logger);
    }
}
