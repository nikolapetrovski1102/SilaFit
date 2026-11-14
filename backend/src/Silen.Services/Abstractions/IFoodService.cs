using System.Text.Json;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>Food lookup for the meal tracker: search the nutrition catalog
/// (plus the user's own foods) and add a food the catalog is missing.
/// Available on every tier - logging meals food-by-food is the Free experience.</summary>
public interface IFoodService
{
    /// <summary>Foods whose name starts with <paramref name="query"/> (or whose barcode
    /// matches it). Queries under two characters return an empty list.</summary>
    Task<ServiceResult<List<FoodNutritionModel>>> SearchAsync(
        Guid userId, string? query, int? take, CancellationToken cancellationToken = default);

    Task<ServiceResult<FoodNutritionModel>> CreateCustomAsync(
        Guid userId, CreateCustomFoodRequest request, CancellationToken cancellationToken = default);

    /// <summary>A package barcode scanned in the meal tracker: the user's own food or the
    /// catalog first, then a live Open Food Facts lookup (saved to the catalog so the next
    /// scan is local). A miss still returns whatever is known about the product as a hint.
    /// Pro and Advanced; a Free account gets <see cref="IFoodScanService.BarcodeTrialLimit"/>
    /// lookups, then a 403 (ProUpgradeRequired) the app answers with the plans.
    /// <paramref name="openFoodFactsOnDevice"/> (current apps): on a miss the server doesn't
    /// call OFF; it answers CheckOpenFoodFacts and the phone asks OFF itself, then posts the
    /// product to <see cref="SaveDeviceOpenFoodFactsProductAsync"/>.</summary>
    Task<ServiceResult<BarcodeLookupResultDto>> LookupBarcodeAsync(
        Guid userId, string? barcode, bool openFoodFactsOnDevice = false, CancellationToken cancellationToken = default);

    /// <summary>The Open Food Facts v2 product response the phone fetched after a
    /// CheckOpenFoodFacts miss. Parsed and plausibility-checked like the server's own OFF
    /// lookups, then saved to the shared catalog. Needs that lookup's one-time ticket
    /// (400 without one), so it can't bypass the Pro gate or write unscanned products.</summary>
    Task<ServiceResult<BarcodeLookupResultDto>> SaveDeviceOpenFoodFactsProductAsync(
        Guid userId, string? barcode, JsonElement openFoodFactsResponse, CancellationToken cancellationToken = default);
}
