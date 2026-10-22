using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Silen.Api.Filters;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>Server-to-server API for the partner website (docs/partner-integration.md).
/// No JWT - the partner authenticates with HTTP Basic, and each body is an AES-256-GCM
/// encrypted payload under a key shared only with the partner.</summary>
[ApiController]
[Route("api/partner")]
[AllowAnonymous]
[TypeFilter(typeof(PartnerBasicAuthFilter))]
[EnableRateLimiting(RateLimitPolicies.Partner)]
public sealed class PartnerController(IPartnerService partnerService, ILogger<PartnerController> logger) : ControllerBase
{
    /// <summary>The lead reached the "use the app" screen: create (or find) their SilaFit
    /// account and give it PRO until the partner cancels.</summary>
    [HttpPost("leads")]
    public async Task<IActionResult> ProvisionLead([FromBody] PartnerEncryptedRequest request, CancellationToken cancellationToken)
    {
        var result = await partnerService.ProvisionLeadAsync(request, cancellationToken);
        return result.ToActionResult(logger);
    }

    /// <summary>The lead ended their subscription on the partner website: PRO ends now.</summary>
    [HttpPost("leads/cancel")]
    public async Task<IActionResult> CancelLead([FromBody] PartnerEncryptedRequest request, CancellationToken cancellationToken)
    {
        var result = await partnerService.CancelLeadAsync(request, cancellationToken);
        return result.ToActionResult(logger);
    }
}
