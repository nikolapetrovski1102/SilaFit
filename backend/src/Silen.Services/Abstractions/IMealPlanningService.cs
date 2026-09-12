using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

public interface IMealPlanningService
{
    Task<ServiceResult<MealDayDto>> GetDayAsync(Guid userId, DateOnly logDateUtc, CancellationToken cancellationToken = default);

    Task<ServiceResult<MealLogModel>> UpsertMealAsync(Guid userId, UpsertMealLogRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<bool>> DeleteMealAsync(Guid userId, Guid mealLogId, CancellationToken cancellationToken = default);

    Task<ServiceResult<UserNutritionTargetsModel>> GetTargetsAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<ServiceResult<UserNutritionTargetsModel>> UpdateTargetsAsync(Guid userId, UpsertNutritionTargetsRequest request, CancellationToken cancellationToken = default);

    /// <summary>Curated meal ideas for <paramref name="month"/> (1-12), or the
    /// caller's current UTC month when null.</summary>
    Task<ServiceResult<List<MealSuggestionModel>>> GetSuggestionsAsync(int? month, CancellationToken cancellationToken = default);
}
