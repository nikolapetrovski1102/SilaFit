using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>
/// The Today dashboard - core tracking, available to any authenticated
/// tier (Guest or Registered). This is the one fully-wired vertical slice.
/// </summary>
[ApiController]
[Route("api/today")]
[Authorize]
public sealed class TodayController(ITodayService todayService, ILogger<TodayController> logger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetDashboard(CancellationToken cancellationToken)
    {
        var result = await todayService.GetDashboardAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("hydration")]
    public async Task<IActionResult> LogHydration([FromBody] LogHydrationRequest request, CancellationToken cancellationToken)
    {
        var result = await todayService.LogHydrationAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("bodyweight")]
    public async Task<IActionResult> LogBodyweight([FromBody] LogBodyweightRequest request, CancellationToken cancellationToken)
    {
        var result = await todayService.LogBodyweightAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("workout/complete")]
    public async Task<IActionResult> CompleteWorkout([FromBody] CompleteWorkoutRequest request, CancellationToken cancellationToken)
    {
        var result = await todayService.CompleteWorkoutAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpGet("workout/history")]
    public async Task<IActionResult> GetWorkoutHistory([FromQuery] DateTime date, CancellationToken cancellationToken)
    {
        var result = await todayService.GetWorkoutHistoryAsync(User.GetUserId(), date, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpGet("exercises/{exerciseId:guid}/history")]
    public async Task<IActionResult> GetExerciseHistory(Guid exerciseId, CancellationToken cancellationToken)
    {
        var result = await todayService.GetExerciseHistoryAsync(User.GetUserId(), exerciseId, cancellationToken);
        return result.ToActionResult(logger);
    }
}
