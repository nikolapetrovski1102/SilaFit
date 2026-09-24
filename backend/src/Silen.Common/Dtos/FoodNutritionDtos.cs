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
}
