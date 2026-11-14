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
                SqlParameterBuilder.Create("@ContentHash", contentHash),
                SqlParameterBuilder.Create("@Barcode", request.Barcode)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, FoodNutritionRowMapper.MapFood, cancellationToken),
            cancellationToken) ?? throw new InvalidOperationException("FoodNutrition_CreateCustom did not return a row.");

    public Task<FoodNutritionModel?> GetByBarcodeAsync(
        Guid userId, string barcode, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.FoodNutrition_GetByBarcode",
            [
                SqlParameterBuilder.Create("@Barcode", barcode),
                SqlParameterBuilder.Create("@UserId", userId)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, FoodNutritionRowMapper.MapFood, cancellationToken),
            cancellationToken);

    public Task<BarcodeProductHintDto?> GetBarcodeSuggestionAsync(
        Guid userId, string barcode, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.FoodNutrition_GetBarcodeSuggestion",
            [
                SqlParameterBuilder.Create("@Barcode", barcode),
                SqlParameterBuilder.Create("@UserId", userId)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, FoodNutritionRowMapper.MapBarcodeSuggestion, cancellationToken),
            cancellationToken);

    public async Task<FoodNutritionModel> SaveOpenFoodFactsAsync(
        OpenFoodFactsProductModel product,
        string name,
        string normalizedName,
        byte[] contentHash,
        string sourceName,
        CancellationToken cancellationToken = default) =>
        await sqlExecutor.QueryAsync(
            "dbo.FoodNutrition_SaveOpenFoodFacts",
            [
                SqlParameterBuilder.Create("@Barcode", product.Barcode),
                SqlParameterBuilder.Create("@Name", name),
                SqlParameterBuilder.Create("@NormalizedName", normalizedName),
                SqlParameterBuilder.Create("@BrandName", product.BrandName),
                SqlParameterBuilder.Create("@SourceUrl", product.SourceUrl),
                SqlParameterBuilder.Create("@ImageUrl", product.ImageUrl),
                SqlParameterBuilder.Create("@ServingSizeG", product.ServingSizeG),
                SqlParameterBuilder.Create("@CaloriesKcal", product.CaloriesKcal),
                SqlParameterBuilder.Create("@ProteinG", product.ProteinG),
                SqlParameterBuilder.Create("@CarbohydrateG", product.CarbohydrateG),
                SqlParameterBuilder.Create("@FatG", product.FatG),
                SqlParameterBuilder.Create("@FiberG", product.FiberG),
                SqlParameterBuilder.Create("@SugarG", product.SugarG),
                SqlParameterBuilder.Create("@SodiumMg", product.SodiumMg),
                SqlParameterBuilder.Create("@ContentHash", contentHash),
                SqlParameterBuilder.Create("@SourceName", sourceName)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, FoodNutritionRowMapper.MapFood, cancellationToken),
            cancellationToken) ?? throw new InvalidOperationException("FoodNutrition_SaveOpenFoodFacts did not return a row.");
}
