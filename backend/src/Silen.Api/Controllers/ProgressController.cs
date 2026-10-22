using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>Progress analytics is an account-gated feature - Registered tier only. The per-exercise
/// endpoints additionally require an active PRO/Advanced subscription, or a rewarded-ad pass.</summary>
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

    [HttpGet("personal-records")]
    public async Task<IActionResult> GetPersonalRecords([FromQuery] int top, CancellationToken cancellationToken)
    {
        var result = await progressService.GetPersonalRecordsAsync(User.GetUserId(), top, cancellationToken);
        return result.ToActionResult(logger);
    }

    /// <summary>PRO/Advanced or an active ad pass - 403 otherwise.</summary>
    [HttpGet("exercises")]
    public async Task<IActionResult> GetTrackedExercises(CancellationToken cancellationToken)
    {
        var result = await progressService.GetTrackedExercisesAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }

    /// <summary>PRO/Advanced or an active ad pass - 403 otherwise.</summary>
    [HttpGet("exercises/{exerciseId:guid}")]
    public async Task<IActionResult> GetExerciseProgress(Guid exerciseId, [FromQuery] int days, CancellationToken cancellationToken)
    {
        var result = await progressService.GetExerciseProgressAsync(User.GetUserId(), exerciseId, days, cancellationToken);
        return result.ToActionResult(logger);
    }

    /// <summary>A Free account's short Progress pass for watching a rewarded video ad - capped per day.</summary>
    [HttpPost("ad-pass")]
    public async Task<IActionResult> GrantAdPass(CancellationToken cancellationToken)
    {
        var result = await progressService.GrantAdPassAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }

    /// <summary>Ends the caller's ad pass early - called when the user leaves the Progress screen.</summary>
    [HttpDelete("ad-pass")]
    public async Task<IActionResult> EndAdPass(CancellationToken cancellationToken)
    {
        var result = await progressService.EndAdPassAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }
}
