using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>The allowance ledger behind food scans - AI meal photos and Free-tier trial
/// barcode lookups (dbo.FoodScans).</summary>
public interface IFoodScanProvider
{
    /// <summary>Atomically claims a scan of <paramref name="kind"/> ("meal" or "barcode"). Paid
    /// (<paramref name="isTrial"/> false): unless <paramref name="dailyLimit"/> scans of that kind
    /// were made since <paramref name="dayStartUtc"/>. Free: unless <paramref name="trialLimit"/>
    /// trial scans of that kind were ever made.</summary>
    Task<FoodScanReservationModel> TryReserveAsync(
        Guid userId, string kind, bool isTrial, DateTime dayStartUtc, int dailyLimit, int trialLimit,
        CancellationToken cancellationToken = default);

    /// <summary>Returns a claimed scan to the allowance (its AI call failed).</summary>
    Task ReleaseAsync(Guid userId, long foodScanId, CancellationToken cancellationToken = default);

    Task<FoodScanUsageModel> GetUsageAsync(Guid userId, DateTime dayStartUtc, CancellationToken cancellationToken = default);
}
