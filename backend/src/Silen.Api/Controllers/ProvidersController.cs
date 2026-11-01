using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>Partner shops with discount codes, for Settings > Providers and the protein nudge.</summary>
[ApiController]
[Route("api/providers")]
[Authorize]
public sealed class ProvidersController(ISupplementProviderService providerService, ILogger<ProvidersController> logger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetActive(CancellationToken cancellationToken) =>
        (await providerService.GetActiveAsync(cancellationToken)).ToActionResult(logger);
}
