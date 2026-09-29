using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Common.Contracts;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>The food catalog behind the meal tracker - open to any authenticated tier.
/// Search covers the shared catalog plus the caller's own foods; POST adds a food the
/// catalog is missing (private to its creator). The scan endpoints (AI meal-photo
/// recognition) are Advanced-only - enforced in <see cref="IFoodScanService"/>.</summary>
[ApiController]
[Route("api/foods")]
[Authorize]
public sealed class FoodsController(
    IFoodService foodService,
    IFoodScanService foodScanService,
    ILogger<FoodsController> logger) : ControllerBase
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

    [HttpGet("scan/quota")]
    public async Task<IActionResult> GetScanQuota(CancellationToken cancellationToken)
    {
        var result = await foodScanService.GetQuotaAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }

    // Multipart rather than base64 JSON: a third smaller on the wire. The app sends
    // a ~1024 px JPEG well under a megabyte; the cap leaves room for a PNG.
    [HttpPost("scan")]
    [RequestSizeLimit(IFoodScanService.MaxImageBytes + 64 * 1024)]
    public async Task<IActionResult> Scan(IFormFile? image, [FromForm] string? mealName, CancellationToken cancellationToken)
    {
        if (image is null || image.Length == 0)
        {
            return BadRequest(ApiResponse.Fail("Choose a photo of your meal."));
        }

        if (image.Length > IFoodScanService.MaxImageBytes)
        {
            return BadRequest(ApiResponse.Fail("That photo is too large. Try another one."));
        }

        using var buffer = new MemoryStream((int)image.Length);
        await image.CopyToAsync(buffer, cancellationToken);
        var result = await foodScanService.ScanAsync(User.GetUserId(), buffer.ToArray(), mealName, cancellationToken);
        return result.ToActionResult(logger);
    }
}
