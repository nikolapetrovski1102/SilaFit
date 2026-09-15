using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>The split library is browsable by anyone; activating a split is core tracking, open to any authenticated tier.</summary>
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
}
