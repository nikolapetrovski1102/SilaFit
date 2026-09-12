using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class MealPlanningProvider(ISqlExecutor sqlExecutor) : IMealPlanningProvider
{
    public Task<UserNutritionTargetsModel?> GetTargetsAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserNutritionTargets_Get",
            [SqlParameterBuilder.Create("@UserId", userId)],
            async reader => await reader.ReadAsync(cancellationToken) ? MealPlanningRowMapper.MapNutritionTargets(reader) : null,
            cancellationToken);

    public async Task<UserNutritionTargetsModel> UpsertTargetsAsync(Guid userId, UpsertNutritionTargetsRequest request, CancellationToken cancellationToken = default) =>
        await sqlExecutor.QueryAsync(
            "dbo.usp_UserNutritionTargets_Upsert",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@TargetCalories", request.TargetCalories),
                SqlParameterBuilder.Create("@TargetProteinG", request.TargetProteinG),
                SqlParameterBuilder.Create("@TargetCarbsG", request.TargetCarbsG),
                SqlParameterBuilder.Create("@TargetFatsG", request.TargetFatsG)
            ],
            async reader => await reader.ReadAsync(cancellationToken) ? MealPlanningRowMapper.MapNutritionTargets(reader) : null,
            cancellationToken) ?? throw new InvalidOperationException("usp_UserNutritionTargets_Upsert did not return a row.");

    public Task<List<MealLogModel>> GetForDateAsync(Guid userId, DateOnly logDateUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_MealLogs_GetForDate",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@LogDateUtc", logDateUtc.ToDateTime(TimeOnly.MinValue))
            ],
            async reader =>
            {
                var meals = new List<MealLogModel>();
                while (await reader.ReadAsync(cancellationToken))
                {
                    meals.Add(MealPlanningRowMapper.MapMealLog(reader));
                }

                return meals;
            },
            cancellationToken);

    public async Task<MealLogModel> UpsertMealAsync(Guid userId, UpsertMealLogRequest request, CancellationToken cancellationToken = default) =>
        await sqlExecutor.QueryAsync(
            "dbo.usp_MealLogs_Upsert",
            [
                SqlParameterBuilder.Create("@MealLogId", request.MealLogId),
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@LogDateUtc", request.LogDateUtc.ToDateTime(TimeOnly.MinValue)),
                SqlParameterBuilder.Create("@MealType", request.MealType),
                SqlParameterBuilder.Create("@Title", request.Title),
                SqlParameterBuilder.Create("@CaloriesKcal", request.CaloriesKcal),
                SqlParameterBuilder.Create("@ProteinG", request.ProteinG),
                SqlParameterBuilder.Create("@CarbsG", request.CarbsG),
                SqlParameterBuilder.Create("@FatsG", request.FatsG),
                SqlParameterBuilder.Create("@Status", request.Status),
                SqlParameterBuilder.Create("@PlannedLocalTime", request.PlannedLocalTime)
            ],
            async reader => await reader.ReadAsync(cancellationToken) ? MealPlanningRowMapper.MapMealLog(reader) : null,
            cancellationToken) ?? throw new InvalidOperationException("usp_MealLogs_Upsert did not return a row.");

    public Task DeleteMealAsync(Guid userId, Guid mealLogId, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_MealLogs_Delete",
            [SqlParameterBuilder.Create("@MealLogId", mealLogId), SqlParameterBuilder.Create("@UserId", userId)],
            cancellationToken);

    public Task<List<MealSuggestionModel>> GetSuggestionsForMonthAsync(int month, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_MealSuggestions_GetForMonth",
            [SqlParameterBuilder.Create("@Month", (byte)month)],
            async reader =>
            {
                var suggestions = new List<MealSuggestionModel>();
                while (await reader.ReadAsync(cancellationToken))
                {
                    suggestions.Add(MealPlanningRowMapper.MapMealSuggestion(reader));
                }

                return suggestions;
            },
            cancellationToken);
}
