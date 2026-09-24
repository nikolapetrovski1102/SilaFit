namespace Silen.Common.Models;

/// <summary>One dbo.FoodNutrition row as returned by FoodNutrition_Search. Every
/// nutrient is per 100 g; null means the source didn't report it.</summary>
public sealed class FoodNutritionModel
{
    public long FoodNutritionId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? BrandName { get; set; }
    public string? Barcode { get; set; }
    public string SourceName { get; set; } = string.Empty;

    /// <summary>The source's own serving size, offered as the default amount when logging.</summary>
    public decimal? ServingSizeG { get; set; }
    public decimal? CaloriesKcal { get; set; }
    public decimal? ProteinG { get; set; }
    public decimal? CarbohydrateG { get; set; }
    public decimal? FatG { get; set; }
    public decimal? FiberG { get; set; }
    public decimal? SugarG { get; set; }
    public decimal? SodiumMg { get; set; }

    /// <summary>True for a food the caller added themselves (private to them).</summary>
    public bool IsCustom { get; set; }
}
