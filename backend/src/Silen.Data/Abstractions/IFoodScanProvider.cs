using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>The per-day allowance ledger behind AI food-photo scans (dbo.FoodScans).</summary>
public interface IFoodScanProvider
{
    /// <summary>Atomically claims a scan unless <paramref name="dailyLimit"/> scans were
    /// already made since <paramref name="dayStartUtc"/>.</summary>
    Task<FoodScanReservationModel> TryReserveAsync(
        Guid userId, DateTime dayStartUtc, int dailyLimit, CancellationToken cancellationToken = default);

    /// <summary>Returns a claimed scan to the allowance (its AI call failed).</summary>
    Task ReleaseAsync(Guid userId, long foodScanId, CancellationToken cancellationToken = default);

    Task<int> CountSinceAsync(Guid userId, DateTime dayStartUtc, CancellationToken cancellationToken = default);
}
