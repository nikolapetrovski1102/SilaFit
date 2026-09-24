using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>Listing the suggested-split library is PRO/Advanced only (enforced in SplitService); a split's detail,
/// the user's own splits and activating a split are core tracking, open to any authenticated tier.</summary>
[ApiController]
[Route("api/splits")]
public sealed class SplitsController(ISplitService splitService, ILogger<SplitsController> logger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetAll(CancellationToken cancellationToken)
    {
        var result = await splitService.GetAllAsync(User.GetUserIdOrNull(), cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpGet("{splitId:guid}")]
    public async Task<IActionResult> GetDetail(Guid splitId, CancellationToken cancellationToken)
    {
        var result = await splitService.GetDetailAsync(splitId, User.GetUserIdOrNull(), cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("activate")]
    [Authorize]
    public async Task<IActionResult> Activate([FromBody] ActivateSplitRequest request, CancellationToken cancellationToken)
    {
        var result = await splitService.ActivateAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    /* ----------------------------- user-owned splits ----------------------------- */

    [HttpGet("mine")]
    [Authorize]
    public async Task<IActionResult> GetMine(CancellationToken cancellationToken)
    {
        var result = await splitService.GetMySplitsAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost]
    [Authorize]
    public async Task<IActionResult> Save([FromBody] UserSplitUpsertRequest request, CancellationToken cancellationToken)
    {
        var result = await splitService.CreateOrUpdateMySplitAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpDelete("{splitId:guid}")]
    [Authorize]
    public async Task<IActionResult> Delete(Guid splitId, CancellationToken cancellationToken)
    {
        var result = await splitService.DeleteMySplitAsync(User.GetUserId(), splitId, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("mine/{splitId:guid}/keep")]
    [Authorize]
    public async Task<IActionResult> Keep(Guid splitId, CancellationToken cancellationToken)
    {
        var result = await splitService.KeepMySplitAsync(User.GetUserId(), splitId, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("days")]
    [Authorize]
    public async Task<IActionResult> SaveDay([FromBody] UserSplitDayUpsertRequest request, CancellationToken cancellationToken)
    {
        var result = await splitService.SaveMySplitDayAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpDelete("days/{splitDayId:guid}")]
    [Authorize]
    public async Task<IActionResult> DeleteDay(Guid splitDayId, CancellationToken cancellationToken)
    {
        var result = await splitService.DeleteMySplitDayAsync(User.GetUserId(), splitDayId, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("day-exercises")]
    [Authorize]
    public async Task<IActionResult> SaveDayExercise([FromBody] UserSplitDayExerciseUpsertRequest request, CancellationToken cancellationToken)
    {
        var result = await splitService.SaveMySplitDayExerciseAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpDelete("day-exercises/{splitDayExerciseId:guid}")]
    [Authorize]
    public async Task<IActionResult> DeleteDayExercise(Guid splitDayExerciseId, CancellationToken cancellationToken)
    {
        var result = await splitService.DeleteMySplitDayExerciseAsync(User.GetUserId(), splitDayExerciseId, cancellationToken);
        return result.ToActionResult(logger);
    }
}
