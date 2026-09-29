using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>The website's support contact form (website/support.html). Anonymous, since
/// the visitor may be locked out of their account or not have one.</summary>
[ApiController]
[Route("api/support")]
[AllowAnonymous]
[EnableRateLimiting(RateLimitPolicies.SupportContact)]
public sealed class SupportController(ISupportService supportService, ILogger<SupportController> logger) : ControllerBase
{
    [HttpPost("contact")]
    public async Task<IActionResult> Contact([FromBody] SupportContactRequest request, CancellationToken cancellationToken)
    {
        var result = await supportService.ContactAsync(request, cancellationToken);
        return result.ToActionResult(logger);
    }
}
