namespace Silen.Common.Models;

/// <summary>The outcome of usp_FoodScan_TryReserve: whether a scan was claimed from
/// today's allowance, how many the user has now used today, and the claimed row
/// (so a failed AI call can give it back).</summary>
public sealed class FoodScanReservationModel
{
    public bool Allowed { get; set; }
    public int UsedToday { get; set; }
    public long? FoodScanId { get; set; }
}
