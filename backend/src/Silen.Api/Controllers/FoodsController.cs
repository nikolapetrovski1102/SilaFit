using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Common.Contracts;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>The food catalog behind the meal tracker - open to any authenticated tier.
/// Search covers the shared catalog plus the caller's own foods; POST adds a food the
/// catalog is missing (private to its creator). barcode/{code} answers a package scan,
/// falling back to Open Food Facts - asked by the phone itself on current apps, which then
/// post the product to barcode/{code}/open-food-facts, or by the server for older ones. label-scan reads a nutrition table
/// photo (any tier, AI consent). The meal-photo scan endpoints are Advanced-only, and
/// barcode lookups Pro (a Free account gets a few) - enforced in the services.</summary>
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

    [HttpGet("barcode/{code}")]
    [EnableRateLimiting(RateLimitPolicies.BarcodeLookup)]
    public async Task<IActionResult> LookupBarcode(
        string code, [FromQuery] bool offOnDevice, CancellationToken cancellationToken)
    {
        var result = await foodService.LookupBarcodeAsync(User.GetUserId(), code, offOnDevice, cancellationToken);
        return result.ToActionResult(logger);
    }

    // What the phone's own Open Food Facts lookup returned, after a CheckOpenFoodFacts
    // miss. A trimmed v2 product response ({status, product}) is a few KB at most.
    [HttpPost("barcode/{code}/open-food-facts")]
    [EnableRateLimiting(RateLimitPolicies.BarcodeLookup)]
    [RequestSizeLimit(64 * 1024)]
    public async Task<IActionResult> SaveDeviceOpenFoodFactsProduct(
        string code, [FromBody] JsonElement product, CancellationToken cancellationToken)
    {
        var result = await foodService.SaveDeviceOpenFoodFactsProductAsync(User.GetUserId(), code, product, cancellationToken);
        return result.ToActionResult(logger);
    }

    // A nutrition-table photo -> per-100 g values for the "add a food" form. Sent larger
    // than a meal photo (~1600 px) so small label print stays legible.
    [HttpPost("label-scan")]
    [EnableRateLimiting(RateLimitPolicies.FoodLabelScan)]
    [RequestSizeLimit(IFoodScanService.MaxImageBytes + 64 * 1024)]
    public async Task<IActionResult> ScanLabel(IFormFile? image, CancellationToken cancellationToken)
    {
        if (image is null || image.Length == 0)
        {
            return BadRequest(ApiResponse.Fail("Choose a photo of the nutrition label."));
        }

        if (image.Length > IFoodScanService.MaxImageBytes)
        {
            return BadRequest(ApiResponse.Fail("That photo is too large. Try another one."));
        }

        using var buffer = new MemoryStream((int)image.Length);
        await image.CopyToAsync(buffer, cancellationToken);
        var result = await foodScanService.ReadLabelAsync(User.GetUserId(), buffer.ToArray(), cancellationToken);
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
