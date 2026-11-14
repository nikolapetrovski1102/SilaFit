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

    /// <summary>Product photo (Open Food Facts), or null.</summary>
    public string? ImageUrl { get; set; }

    /// <summary>True for a food the caller added themselves (private to them).</summary>
    public bool IsCustom { get; set; }
}

/// <summary>One product read from the Open Food Facts API (per 100 g), as the barcode
/// lookup saves it into the catalog. Null nutrients weren't reported.</summary>
public sealed class OpenFoodFactsProductModel
{
    public string Barcode { get; set; } = string.Empty;
    public string? Name { get; set; }
    public string? BrandName { get; set; }
    public string? ImageUrl { get; set; }
    public decimal? ServingSizeG { get; set; }
    public decimal? CaloriesKcal { get; set; }
    public decimal? ProteinG { get; set; }
    public decimal? CarbohydrateG { get; set; }
    public decimal? FatG { get; set; }
    public decimal? FiberG { get; set; }
    public decimal? SugarG { get; set; }
    public decimal? SodiumMg { get; set; }

    /// <summary>Where the product's page is. Defaults to its Open Food Facts page; a partner
    /// catalog product sets its own shop page (or leaves it, and gets none).</summary>
    public string? SourceUrl
    {
        get => sourceUrl ?? (IsPartnerProduct ? null : $"https://world.openfoodfacts.org/product/{Uri.EscapeDataString(Barcode)}");
        set
        {
            sourceUrl = value;
            IsPartnerProduct = true;
        }
    }

    private string? sourceUrl;

    /// <summary>True once <see cref="SourceUrl"/> was set, i.e. the product came from a
    /// partner catalog rather than Open Food Facts.</summary>
    public bool IsPartnerProduct { get; private set; }

    /// <summary>All four values the tracker needs to count the food.</summary>
    public bool HasHeadlineNutrients =>
        CaloriesKcal is not null && ProteinG is not null && CarbohydrateG is not null && FatG is not null;
}
