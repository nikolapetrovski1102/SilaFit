using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>AI-generated progress analytics. The monthly report is Pro/Advanced; the weekly report
/// (and its meal/split recommendations) is Advanced-only - see ISubscriptionGate.</summary>
[ApiController]
[Route("api/analytics")]
[Authorize(Policy = AuthorizationPolicies.RequireLinkedAccount)]
[EnableRateLimiting(RateLimitPolicies.Analytics)]
public sealed class AnalyticsController(IAnalyticsService analyticsService, ILogger<AnalyticsController> logger) : ControllerBase
{
    [HttpGet("monthly")]
    public async Task<IActionResult> GetMonthly(
        [FromQuery] int? year, [FromQuery] int? month, [FromQuery] bool refresh, CancellationToken cancellationToken)
    {
        var result = await analyticsService.GetMonthlyAsync(User.GetUserId(), year, month, refresh, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpGet("weekly")]
    public async Task<IActionResult> GetWeekly(
        [FromQuery] int? year, [FromQuery] int? week, [FromQuery] bool refresh, CancellationToken cancellationToken)
    {
        var result = await analyticsService.GetWeeklyAsync(User.GetUserId(), year, week, refresh, cancellationToken);
        return result.ToActionResult(logger);
    }
}
