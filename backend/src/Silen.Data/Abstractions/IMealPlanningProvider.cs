using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IMealPlanningProvider
{
    Task<UserNutritionTargetsModel?> GetTargetsAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<UserNutritionTargetsModel> UpsertTargetsAsync(Guid userId, UpsertNutritionTargetsRequest request, CancellationToken cancellationToken = default);

    Task<List<MealLogModel>> GetForDateAsync(Guid userId, DateOnly logDateUtc, CancellationToken cancellationToken = default);

    Task<MealLogModel> UpsertMealAsync(Guid userId, UpsertMealLogRequest request, CancellationToken cancellationToken = default);

    Task DeleteMealAsync(Guid userId, Guid mealLogId, CancellationToken cancellationToken = default);

    Task<List<MealSuggestionModel>> GetSuggestionsForMonthAsync(int month, CancellationToken cancellationToken = default);

    /// <summary>Logged date + calorie pairs in [fromDateUtc, toDateUtc]. Used by AnalyticsProvider
    /// to derive AvgCaloriesLogged now that CaloriesKcal can no longer be aggregated in T-SQL.</summary>
    Task<List<(DateOnly LogDateUtc, int CaloriesKcal)>> GetCaloriesInRangeAsync(Guid userId, DateOnly fromDateUtc, DateOnly toDateUtc, CancellationToken cancellationToken = default);
}
