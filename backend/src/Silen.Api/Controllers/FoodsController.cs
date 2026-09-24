using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>The food catalog behind the meal tracker - open to any authenticated tier.
/// Search covers the shared catalog plus the caller's own foods; POST adds a food the
/// catalog is missing (private to its creator).</summary>
[ApiController]
[Route("api/foods")]
[Authorize]
public sealed class FoodsController(IFoodService foodService, ILogger<FoodsController> logger) : ControllerBase
{
    [HttpGet("search")]
    public async Task<IActionResult> Search([FromQuery] string? q, [FromQuery] int? take, CancellationToken cancellationToken)
    {
        var result = await foodService.SearchAsync(User.GetUserId(), q, take, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost]
    public async Task<IActionResult> CreateCustom([FromBody] CreateCustomFoodRequest request, CancellationToken cancellationToken)
    {
        var result = await foodService.CreateCustomAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }
}
