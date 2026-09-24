using Microsoft.Data.SqlClient;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>dbo.FoodNutrition rows (FoodNutrition.sql). Nutrients are per 100 g.</summary>
public static class FoodNutritionRowMapper
{
    public static FoodNutritionModel MapFood(SqlDataReader reader) => new()
    {
        FoodNutritionId = reader.GetInt64(reader.GetOrdinal("FoodNutritionId")),
        Name = reader.GetStringValue("Name"),
        BrandName = reader.GetNullableString("BrandName"),
        Barcode = reader.GetNullableString("Barcode"),
        SourceName = reader.GetStringValue("SourceName"),
        ServingSizeG = reader.GetNullableDecimal("ServingSizeG"),
        CaloriesKcal = reader.GetNullableDecimal("CaloriesKcal"),
        ProteinG = reader.GetNullableDecimal("ProteinG"),
        CarbohydrateG = reader.GetNullableDecimal("CarbohydrateG"),
        FatG = reader.GetNullableDecimal("FatG"),
        FiberG = reader.GetNullableDecimal("FiberG"),
        SugarG = reader.GetNullableDecimal("SugarG"),
        SodiumMg = reader.GetNullableDecimal("SodiumMg"),
        IsCustom = reader.GetBoolValue("IsCustom")
    };
}
