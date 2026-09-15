using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>Meal planning/logging and nutrition targets - open to any authenticated tier, guests included.</summary>
[ApiController]
[Route("api/meals")]
[Authorize]
public sealed class MealPlanningController(IMealPlanningService mealPlanningService, ILogger<MealPlanningController> logger) : ControllerBase
{
    [HttpGet("day")]
    public async Task<IActionResult> GetDay([FromQuery] DateOnly date, CancellationToken cancellationToken)
    {
        var result = await mealPlanningService.GetDayAsync(User.GetUserId(), date, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("log")]
    public async Task<IActionResult> CreateLog([FromBody] UpsertMealLogRequest request, CancellationToken cancellationToken)
    {
        var result = await mealPlanningService.UpsertMealAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPut("log/{mealLogId:guid}")]
    public async Task<IActionResult> UpdateLog(Guid mealLogId, [FromBody] UpsertMealLogRequest request, CancellationToken cancellationToken)
    {
        request.MealLogId = mealLogId;
        var result = await mealPlanningService.UpsertMealAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpDelete("log/{mealLogId:guid}")]
    public async Task<IActionResult> DeleteLog(Guid mealLogId, CancellationToken cancellationToken)
    {
        var result = await mealPlanningService.DeleteMealAsync(User.GetUserId(), mealLogId, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpGet("targets")]
    public async Task<IActionResult> GetTargets(CancellationToken cancellationToken)
    {
        var result = await mealPlanningService.GetTargetsAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPut("targets")]
    public async Task<IActionResult> UpdateTargets([FromBody] UpsertNutritionTargetsRequest request, CancellationToken cancellationToken)
    {
        var result = await mealPlanningService.UpdateTargetsAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    /// <summary>Curated meal ideas for the given month (1-12); defaults to the current UTC
    /// month. Scored against the caller's nutrition targets and returned best-first.</summary>
    [HttpGet("suggestions")]
    public async Task<IActionResult> GetSuggestions([FromQuery] int? month, CancellationToken cancellationToken)
    {
        var result = await mealPlanningService.GetSuggestionsAsync(User.GetUserId(), month, cancellationToken);
        return result.ToActionResult(logger);
    }
}
