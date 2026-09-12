using Microsoft.Extensions.Options;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class MealPlanningProvider : IMealPlanningProvider
{
    private readonly ISqlExecutor _sqlExecutor;
    private readonly byte[] _key;

    public MealPlanningProvider(ISqlExecutor sqlExecutor, IOptions<EncryptionOptions> encryptionOptions)
    {
        _sqlExecutor = sqlExecutor;
        _key = Convert.FromBase64String(encryptionOptions.Value.MasterKeyBase64);
    }

    public Task<UserNutritionTargetsModel?> GetTargetsAsync(Guid userId, CancellationToken cancellationToken = default) =>
        _sqlExecutor.QueryAsync(
            "dbo.usp_UserNutritionTargets_Get",
            [SqlParameterBuilder.Create("@UserId", userId)],
            async reader => await reader.ReadAsync(cancellationToken) ? MealPlanningRowMapper.MapNutritionTargets(reader, _key) : null,
            cancellationToken);

    public async Task<UserNutritionTargetsModel> UpsertTargetsAsync(Guid userId, UpsertNutritionTargetsRequest request, CancellationToken cancellationToken = default) =>
        await _sqlExecutor.QueryAsync(
            "dbo.usp_UserNutritionTargets_Upsert",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@TargetCalories", FieldCipher.EncryptInt(request.TargetCalories, _key)),
                SqlParameterBuilder.Create("@TargetProteinG", FieldCipher.EncryptInt(request.TargetProteinG, _key)),
                SqlParameterBuilder.Create("@TargetCarbsG", FieldCipher.EncryptInt(request.TargetCarbsG, _key)),
                SqlParameterBuilder.Create("@TargetFatsG", FieldCipher.EncryptInt(request.TargetFatsG, _key))
            ],
            async reader => await reader.ReadAsync(cancellationToken) ? MealPlanningRowMapper.MapNutritionTargets(reader, _key) : null,
            cancellationToken) ?? throw new InvalidOperationException("usp_UserNutritionTargets_Upsert did not return a row.");

    public Task<List<MealLogModel>> GetForDateAsync(Guid userId, DateOnly logDateUtc, CancellationToken cancellationToken = default) =>
        _sqlExecutor.QueryAsync(
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
                    meals.Add(MealPlanningRowMapper.MapMealLog(reader, _key));
                }

                return meals;
            },
            cancellationToken);

    public async Task<MealLogModel> UpsertMealAsync(Guid userId, UpsertMealLogRequest request, CancellationToken cancellationToken = default) =>
        await _sqlExecutor.QueryAsync(
            "dbo.usp_MealLogs_Upsert",
            [
                SqlParameterBuilder.Create("@MealLogId", request.MealLogId),
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@LogDateUtc", request.LogDateUtc.ToDateTime(TimeOnly.MinValue)),
                SqlParameterBuilder.Create("@MealType", request.MealType),
                SqlParameterBuilder.Create("@Title", FieldCipher.EncryptString(request.Title, _key)),
                SqlParameterBuilder.Create("@CaloriesKcal", FieldCipher.EncryptInt(request.CaloriesKcal, _key)),
                SqlParameterBuilder.Create("@ProteinG", FieldCipher.EncryptInt(request.ProteinG, _key)),
                SqlParameterBuilder.Create("@CarbsG", FieldCipher.EncryptInt(request.CarbsG, _key)),
                SqlParameterBuilder.Create("@FatsG", FieldCipher.EncryptInt(request.FatsG, _key)),
                SqlParameterBuilder.Create("@Status", request.Status),
                SqlParameterBuilder.Create("@PlannedLocalTime", request.PlannedLocalTime)
            ],
            async reader => await reader.ReadAsync(cancellationToken) ? MealPlanningRowMapper.MapMealLog(reader, _key) : null,
            cancellationToken) ?? throw new InvalidOperationException("usp_MealLogs_Upsert did not return a row.");

    public Task DeleteMealAsync(Guid userId, Guid mealLogId, CancellationToken cancellationToken = default) =>
        _sqlExecutor.ExecuteAsync(
            "dbo.usp_MealLogs_Delete",
            [SqlParameterBuilder.Create("@MealLogId", mealLogId), SqlParameterBuilder.Create("@UserId", userId)],
            cancellationToken);

    public Task<List<MealSuggestionModel>> GetSuggestionsForMonthAsync(int month, CancellationToken cancellationToken = default) =>
        _sqlExecutor.QueryAsync(
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

    public Task<List<(DateOnly LogDateUtc, int CaloriesKcal)>> GetCaloriesInRangeAsync(Guid userId, DateOnly fromDateUtc, DateOnly toDateUtc, CancellationToken cancellationToken = default) =>
        _sqlExecutor.QueryAsync(
            "dbo.usp_MealLogs_GetCaloriesInRange",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@FromDateUtc", fromDateUtc.ToDateTime(TimeOnly.MinValue)),
                SqlParameterBuilder.Create("@ToDateUtc", toDateUtc.ToDateTime(TimeOnly.MinValue))
            ],
            async reader =>
            {
                var entries = new List<(DateOnly, int)>();
                while (await reader.ReadAsync(cancellationToken))
                {
                    entries.Add((
                        DateOnly.FromDateTime(reader.GetDateTimeValue("LogDateUtc")),
                        FieldCipher.DecryptInt(reader.GetBytesValue("CaloriesKcal"), _key)));
                }

                return entries;
            },
            cancellationToken);
}
