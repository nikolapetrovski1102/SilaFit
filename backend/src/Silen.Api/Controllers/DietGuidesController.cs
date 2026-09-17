using Microsoft.AspNetCore.Mvc;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>Imported long-form diet guides. Shipped reference reading, so the whole
/// surface is anonymous and read-only.</summary>
[ApiController]
[Route("api/diet-guides")]
public sealed class DietGuidesController(IDietGuideService dietGuideService, ILogger<DietGuidesController> logger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetAll(CancellationToken cancellationToken)
    {
        var result = await dietGuideService.GetAllAsync(cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpGet("{dietGuideId:guid}")]
    public async Task<IActionResult> GetDetail(Guid dietGuideId, CancellationToken cancellationToken)
    {
        var result = await dietGuideService.GetDetailAsync(dietGuideId, cancellationToken);
        return result.ToActionResult(logger);
    }
}
