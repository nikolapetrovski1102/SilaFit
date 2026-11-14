using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>The food-nutrition catalog (dbo.FoodNutrition, per-100 g values) the
/// meal tracker searches, plus the private foods a user adds when the catalog
/// doesn't have what they ate.</summary>
public interface IFoodNutritionProvider
{
    /// <summary>Prefix search on <paramref name="normalizedQuery"/> (or an exact barcode)
    /// over the shared catalog plus <paramref name="userId"/>'s own foods.</summary>
    Task<List<FoodNutritionModel>> SearchAsync(
        Guid userId, string normalizedQuery, int take, CancellationToken cancellationToken = default);

    /// <summary>Inserts a user-owned food and returns the stored row.</summary>
    Task<FoodNutritionModel> CreateCustomAsync(
        Guid userId,
        CreateCustomFoodRequest request,
        string normalizedName,
        string sourceFoodId,
        byte[] contentHash,
        CancellationToken cancellationToken = default);

    /// <summary>The food with this exact barcode and all four headline nutrients: the
    /// user's own first, then the catalog by source priority. Null when there is none.</summary>
    Task<FoodNutritionModel?> GetByBarcodeAsync(
        Guid userId, string barcode, CancellationToken cancellationToken = default);

    /// <summary>What other users named this barcode product (name, brand, serving - no
    /// nutrition), to prefill the "add it" form. Null when nobody else has saved it.
    /// Saving it twice with matching nutrition, by two users, makes it a shared
    /// 'SilaFit Community' food (dbo.foodnutrition_promotebarcode).</summary>
    Task<BarcodeProductHintDto?> GetBarcodeSuggestionAsync(
        Guid userId, string barcode, CancellationToken cancellationToken = default);

    /// <summary>Adds (or refreshes) a product fetched live from Open Food Facts - or a
    /// partner catalog, named by <paramref name="sourceName"/> - in the shared catalog,
    /// keyed by its barcode like the importer's rows.</summary>
    Task<FoodNutritionModel> SaveOpenFoodFactsAsync(
        OpenFoodFactsProductModel product,
        string name,
        string normalizedName,
        byte[] contentHash,
        string sourceName,
        CancellationToken cancellationToken = default);

    /// <summary>The source name of foods fetched live from Open Food Facts.</summary>
    const string OpenFoodFactsSourceName = "Open Food Facts";
}
