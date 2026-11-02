using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>The allowance ledger behind shared-link scans (dbo.LinkScans) and the shared
/// cache of what the AI read from each public post (dbo.LinkScanCache).</summary>
public interface ILinkScanProvider
{
    /// <summary>Atomically claims a scan of <paramref name="kind"/>: within
    /// <paramref name="dailyLimit"/> of that kind since <paramref name="dayStartUtc"/>, or, when
    /// <paramref name="isTrial"/>, within <paramref name="trialLimit"/> trial scans ever.</summary>
    Task<LinkScanReservationModel> TryReserveAsync(
        Guid userId, string kind, bool isTrial, DateTime dayStartUtc, int dailyLimit, int trialLimit,
        CancellationToken cancellationToken = default);

    /// <summary>Returns a claimed scan to the allowance (the work behind it failed).</summary>
    Task ReleaseAsync(Guid userId, long linkScanId, CancellationToken cancellationToken = default);

    Task<LinkScanUsageModel> GetUsageAsync(Guid userId, DateTime dayStartUtc, CancellationToken cancellationToken = default);

    Task<string?> GetCachedAsync(string provider, string videoId, CancellationToken cancellationToken = default);

    Task PutCachedAsync(string provider, string videoId, string resultJson, CancellationToken cancellationToken = default);
}
