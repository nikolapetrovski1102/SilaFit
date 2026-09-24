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
}
