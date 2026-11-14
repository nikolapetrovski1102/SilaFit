using Silen.Common.Models;

namespace Silen.Common.Dtos;

/// <summary>A food the user couldn't find in the catalog. Nutrients are per 100 g,
/// matching every catalog row, so the meal tracker scales them the same way.</summary>
public sealed class CreateCustomFoodRequest
{
    public string Name { get; set; } = string.Empty;
    public string? BrandName { get; set; }
    public decimal? ServingSizeG { get; set; }
    public decimal CaloriesKcal { get; set; }
    public decimal ProteinG { get; set; }
    public decimal CarbohydrateG { get; set; }
    public decimal FatG { get; set; }
    public decimal? FiberG { get; set; }
    public decimal? SugarG { get; set; }
    public decimal? SodiumMg { get; set; }

    /// <summary>The package barcode when the food was added after a scan the catalog
    /// missed, so scanning it again finds this food.</summary>
    public string? Barcode { get; set; }
}

/// <summary>A barcode scan from the meal tracker. <see cref="Food"/> is set when the
/// catalog (or a live Open Food Facts lookup) has the product with usable nutrition.
/// Otherwise <see cref="Hint"/> may still carry what is known about the product, so
/// the "add it" form starts filled in.</summary>
public sealed class BarcodeLookupResultDto
{
    public string Barcode { get; set; } = string.Empty;
    public bool Found => Food is not null;
    public FoodNutritionModel? Food { get; set; }
    public BarcodeProductHintDto? Hint { get; set; }

    /// <summary>Not in the catalog: the app should ask Open Food Facts from the device and
    /// post what it finds to barcode/{code}/open-food-facts. Only for apps that asked for it.</summary>
    public bool CheckOpenFoodFacts { get; set; }
}

public sealed class BarcodeProductHintDto
{
    public string? Name { get; set; }
    public string? BrandName { get; set; }
    public string? ImageUrl { get; set; }
    public decimal? ServingSizeG { get; set; }
}

/// <summary>A nutrition-table photo read by the vision model. Values are per 100 g
/// (converted by the model when the label only gives them per serving); null means
/// the label didn't show it.</summary>
public sealed class NutritionLabelResultDto
{
    /// <summary>False when the photo doesn't show a nutrition table.</summary>
    public bool IsLabel { get; set; }
    public string? ProductName { get; set; }
    public string? BrandName { get; set; }
    public decimal? ServingSizeG { get; set; }
    public decimal? CaloriesKcal { get; set; }
    public decimal? ProteinG { get; set; }
    public decimal? CarbohydrateG { get; set; }
    public decimal? FatG { get; set; }
    public decimal? FiberG { get; set; }
    public decimal? SugarG { get; set; }
    public decimal? SodiumMg { get; set; }
}
