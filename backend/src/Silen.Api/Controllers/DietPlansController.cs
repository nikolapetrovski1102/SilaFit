using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>The diet plan library is browsable by anyone; building/editing a plan of
/// one's own - and choosing/activating one - is open to any authenticated tier.</summary>
[ApiController]
[Route("api/diet-plans")]
public sealed class DietPlansController(
    IDietPlanService dietPlanService,
    IWeeklyPlanGenerationService weeklyPlanGenerationService,
    ILogger<DietPlansController> logger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetAll(CancellationToken cancellationToken)
    {
        var result = await dietPlanService.GetAllAsync(User.GetUserIdOrNull(), cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpGet("{dietPlanId:guid}")]
    public async Task<IActionResult> GetDetail(Guid dietPlanId, CancellationToken cancellationToken)
    {
        var result = await dietPlanService.GetDetailAsync(dietPlanId, User.GetUserIdOrNull(), cancellationToken);
        return result.ToActionResult(logger);
    }

    /// <summary>The caller's currently active plan with its days/meals, or null when
    /// none is active. Backs the Nutrition screen's "active plan" section.</summary>
    [HttpGet("active")]
    [Authorize]
    public async Task<IActionResult> GetActive(CancellationToken cancellationToken)
    {
        var result = await dietPlanService.GetActiveAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }

    /// <summary>Makes a visible plan the caller's active one.</summary>
    [HttpPost("{dietPlanId:guid}/activate")]
    [Authorize]
    public async Task<IActionResult> Activate(Guid dietPlanId, CancellationToken cancellationToken)
    {
        var result = await dietPlanService.ActivateAsync(User.GetUserId(), dietPlanId, cancellationToken);
        return result.ToActionResult(logger);
    }

    /// <summary>Builds a fresh weekly plan for the caller from their calorie/macro
    /// targets and activates it. The on-demand counterpart of the Sunday batch.</summary>
    [HttpPost("generate")]
    [Authorize]
    public async Task<IActionResult> Generate(CancellationToken cancellationToken)
    {
        var result = await weeklyPlanGenerationService.GenerateDietPlanForUserAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }

    /* ----------------------------- user-owned diet plans ----------------------------- */

    [HttpGet("mine")]
    [Authorize]
    public async Task<IActionResult> GetMine(CancellationToken cancellationToken)
    {
        var result = await dietPlanService.GetMyPlansAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost]
    [Authorize]
    public async Task<IActionResult> Save([FromBody] UserDietPlanUpsertRequest request, CancellationToken cancellationToken)
    {
        var result = await dietPlanService.CreateOrUpdateMyPlanAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpDelete("{dietPlanId:guid}")]
    [Authorize]
    public async Task<IActionResult> Delete(Guid dietPlanId, CancellationToken cancellationToken)
    {
        var result = await dietPlanService.DeleteMyPlanAsync(User.GetUserId(), dietPlanId, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("mine/{dietPlanId:guid}/keep")]
    [Authorize]
    public async Task<IActionResult> Keep(Guid dietPlanId, CancellationToken cancellationToken)
    {
        var result = await dietPlanService.KeepMyPlanAsync(User.GetUserId(), dietPlanId, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("days")]
    [Authorize]
    public async Task<IActionResult> SaveDay([FromBody] UserDietPlanDayUpsertRequest request, CancellationToken cancellationToken)
    {
        var result = await dietPlanService.SaveMyPlanDayAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpDelete("days/{dietPlanDayId:guid}")]
    [Authorize]
    public async Task<IActionResult> DeleteDay(Guid dietPlanDayId, CancellationToken cancellationToken)
    {
        var result = await dietPlanService.DeleteMyPlanDayAsync(User.GetUserId(), dietPlanDayId, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("meals")]
    [Authorize]
    public async Task<IActionResult> SaveMeal([FromBody] UserDietPlanMealUpsertRequest request, CancellationToken cancellationToken)
    {
        var result = await dietPlanService.SaveMyPlanMealAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpDelete("meals/{dietPlanMealId:guid}")]
    [Authorize]
    public async Task<IActionResult> DeleteMeal(Guid dietPlanMealId, CancellationToken cancellationToken)
    {
        var result = await dietPlanService.DeleteMyPlanMealAsync(User.GetUserId(), dietPlanMealId, cancellationToken);
        return result.ToActionResult(logger);
    }
}
