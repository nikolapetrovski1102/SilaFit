namespace Silen.Common.Models;

/// <summary>The outcome of usp_FoodScan_TryReserve: whether a scan was claimed, how many
/// now count against the limit that applied, and the claimed row (so a failed AI call can
/// give it back).</summary>
public sealed class FoodScanReservationModel
{
    public bool Allowed { get; set; }

    /// <summary>Scans counted against the limit that applied, including this one when allowed:
    /// today's scans of that kind for a paid tier, lifetime trial scans of that kind for Free.</summary>
    public int Used { get; set; }

    public long? FoodScanId { get; set; }
}

/// <summary>How many AI food scans the user has made (dbo.usp_FoodScan_Usage).</summary>
public sealed class FoodScanUsageModel
{
    /// <summary>Paid meal-photo scans since the user's local midnight.</summary>
    public int MealToday { get; set; }

    /// <summary>Lifetime Free-tier trial barcode lookups.</summary>
    public int BarcodeTrialUsed { get; set; }
}
