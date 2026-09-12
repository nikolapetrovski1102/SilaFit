using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>AI-generated monthly analytics - Pro/Advanced only (see ISubscriptionGate).</summary>
[ApiController]
[Route("api/analytics")]
[Authorize(Policy = AuthorizationPolicies.RequireLinkedAccount)]
public sealed class AnalyticsController(IAnalyticsService analyticsService, ILogger<AnalyticsController> logger) : ControllerBase
{
    [HttpGet("monthly")]
    public async Task<IActionResult> GetMonthly(
        [FromQuery] int? year, [FromQuery] int? month, [FromQuery] bool refresh, CancellationToken cancellationToken)
    {
        var result = await analyticsService.GetMonthlyAsync(User.GetUserId(), year, month, refresh, cancellationToken);
        return result.ToActionResult(logger);
    }
}
