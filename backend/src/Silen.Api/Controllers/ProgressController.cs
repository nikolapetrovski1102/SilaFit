using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>Progress analytics is an account-gated feature - Registered tier only.</summary>
[ApiController]
[Route("api/progress")]
[Authorize(Policy = AuthorizationPolicies.RequireLinkedAccount)]
public sealed class ProgressController(IProgressService progressService, ILogger<ProgressController> logger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetOverview([FromQuery] int days, CancellationToken cancellationToken)
    {
        var result = await progressService.GetOverviewAsync(User.GetUserId(), days, cancellationToken);
        return result.ToActionResult(logger);
    }
}
