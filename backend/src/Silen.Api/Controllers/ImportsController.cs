using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>"Share to SilaFit": a TikTok link shared into the app comes back as a workout or a
/// meal to review. Tier rules and allowances are enforced in <see cref="ILinkImportService"/>.</summary>
[ApiController]
[Route("api/imports")]
[Authorize]
public sealed class ImportsController(
    ILinkImportService linkImportService,
    ILogger<ImportsController> logger) : ControllerBase
{
    [HttpGet("link/quota")]
    public async Task<IActionResult> GetLinkQuota(CancellationToken cancellationToken)
    {
        var result = await linkImportService.GetQuotaAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("link")]
    public async Task<IActionResult> ImportLink([FromBody] LinkImportRequest request, CancellationToken cancellationToken)
    {
        var result = await linkImportService.ImportAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }
}
