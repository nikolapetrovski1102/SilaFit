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
}
