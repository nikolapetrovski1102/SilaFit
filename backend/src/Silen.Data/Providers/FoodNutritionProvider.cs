using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

/// <inheritdoc cref="IFoodNutritionProvider"/>
public sealed class FoodNutritionProvider(ISqlExecutor sqlExecutor) : IFoodNutritionProvider
{
    public Task<List<FoodNutritionModel>> SearchAsync(
        Guid userId, string normalizedQuery, int take, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.FoodNutrition_Search",
            [
                SqlParameterBuilder.Create("@Query", normalizedQuery),
                SqlParameterBuilder.Create("@Take", take),
                SqlParameterBuilder.Create("@UserId", userId)
            ],
            reader => SqlResultSetReader.ReadListAsync(reader, FoodNutritionRowMapper.MapFood, cancellationToken),
            cancellationToken);

    public async Task<FoodNutritionModel> CreateCustomAsync(
        Guid userId,
        CreateCustomFoodRequest request,
        string normalizedName,
        string sourceFoodId,
        byte[] contentHash,
        CancellationToken cancellationToken = default) =>
        await sqlExecutor.QueryAsync(
            "dbo.FoodNutrition_CreateCustom",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@Name", request.Name),
                SqlParameterBuilder.Create("@NormalizedName", normalizedName),
                SqlParameterBuilder.Create("@BrandName", request.BrandName),
                SqlParameterBuilder.Create("@ServingSizeG", request.ServingSizeG),
                SqlParameterBuilder.Create("@CaloriesKcal", request.CaloriesKcal),
                SqlParameterBuilder.Create("@ProteinG", request.ProteinG),
                SqlParameterBuilder.Create("@CarbohydrateG", request.CarbohydrateG),
                SqlParameterBuilder.Create("@FatG", request.FatG),
                SqlParameterBuilder.Create("@FiberG", request.FiberG),
                SqlParameterBuilder.Create("@SugarG", request.SugarG),
                SqlParameterBuilder.Create("@SodiumMg", request.SodiumMg),
                SqlParameterBuilder.Create("@SourceFoodId", sourceFoodId),
                SqlParameterBuilder.Create("@ContentHash", contentHash)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, FoodNutritionRowMapper.MapFood, cancellationToken),
            cancellationToken) ?? throw new InvalidOperationException("FoodNutrition_CreateCustom did not return a row.");
}
