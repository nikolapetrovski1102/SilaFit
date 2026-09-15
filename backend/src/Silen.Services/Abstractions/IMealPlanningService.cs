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

    /// <summary>Re-derives profile-based nutrition targets after a profile change
    /// (weight/height/age/gender/goal/activity). No-op when the user has set their
    /// own targets manually (<see cref="UserNutritionTargetsModel.IsManualOverride"/>).</summary>
    Task<ServiceResult<UserNutritionTargetsModel>> RecomputeTargetsAsync(Guid userId, UserProfileModel profile, CancellationToken cancellationToken = default);

    /// <summary>Curated meal ideas for <paramref name="month"/> (1-12), or the
    /// caller's current UTC month when null, scored against the caller's own
    /// nutrition targets and returned best-first.</summary>
    Task<ServiceResult<List<MealSuggestionModel>>> GetSuggestionsAsync(Guid userId, int? month, CancellationToken cancellationToken = default);
}
