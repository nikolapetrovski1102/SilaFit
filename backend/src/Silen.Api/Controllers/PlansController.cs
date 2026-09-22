using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>The plan catalog is browsable by anyone; purchasing is a buy feature and requires a linked account.</summary>
[ApiController]
[Route("api/plans")]
public sealed class PlansController(IPlanService planService, ILogger<PlansController> logger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetCatalog(CancellationToken cancellationToken)
    {
        var result = await planService.GetCatalogAsync(cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpGet("current")]
    [Authorize]
    public async Task<IActionResult> GetCurrent(CancellationToken cancellationToken)
    {
        var result = await planService.GetCurrentAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("purchase")]
    [Authorize(Policy = AuthorizationPolicies.RequireLinkedAccount)]
    public async Task<IActionResult> Purchase([FromBody] PurchaseRequest request, CancellationToken cancellationToken)
    {
        var result = await planService.PurchaseAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    /// <summary>Verifies a completed native App Store / Play Store purchase server-side and,
    /// if it's genuinely active, grants the plan its verified product id maps to.</summary>
    [HttpPost("purchase/verify")]
    [Authorize(Policy = AuthorizationPolicies.RequireLinkedAccount)]
    public async Task<IActionResult> VerifyPurchase([FromBody] VerifyPurchaseRequest request, CancellationToken cancellationToken)
    {
        var result = await planService.VerifyPurchaseAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }
}
