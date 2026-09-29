namespace Silen.Common.Dtos;

/// <summary>What the AI saw in a meal photo, ready for the meal tracker to drop in as
/// ingredients. Nutrients are per 100 g like every catalog food, with an estimated
/// portion, so the tracker scales and re-steps them exactly as it does catalog foods.</summary>
public sealed class FoodScanResultDto
{
    /// <summary>False when the photo doesn't show food - <see cref="Items"/> is then empty.</summary>
    public bool IsFood { get; set; }
    public string DishName { get; set; } = string.Empty;
    public List<FoodScanItemDto> Items { get; set; } = [];

    /// <summary>One short caveat from the model (e.g. "sauce hides the portion"), or empty.</summary>
    public string Notes { get; set; } = string.Empty;
    public FoodScanQuotaDto Quota { get; set; } = new();
}

public sealed class FoodScanItemDto
{
    public string Name { get; set; } = string.Empty;
    public decimal EstimatedGrams { get; set; }
    public decimal CaloriesKcal { get; set; }
    public decimal ProteinG { get; set; }
    public decimal CarbohydrateG { get; set; }
    public decimal FatG { get; set; }
    public decimal? FiberG { get; set; }

    /// <summary>Not visible in the photo but almost certainly there - cooking oil, a
    /// dressing, butter in the mash. Shown as "likely" so the user can drop it.</summary>
    public bool IsAssumed { get; set; }

    /// <summary>"high", "medium" or "low".</summary>
    public string Confidence { get; set; } = "medium";
}

/// <summary>The caller's AI food-scan allowance for their current local day.</summary>
public sealed class FoodScanQuotaDto
{
    /// <summary>False below the Advanced tier - scanning isn't offered at all.</summary>
    public bool IsAvailable { get; set; }
    public int DailyLimit { get; set; }
    public int UsedToday { get; set; }
    public int RemainingToday { get; set; }
}
