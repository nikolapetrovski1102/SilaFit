using System.Collections.Concurrent;
using Silen.Services.Abstractions;

namespace Silen.Services.Helpers;

/// <summary>
/// In-process, per-user, per-report-kind rate gate for the places the API spends
/// money per call: <c>GET /api/analytics/monthly?refresh=true</c> and
/// <c>GET /api/analytics/weekly?refresh=true</c>. The framework rate limiter bounds
/// total requests, but without this a single paid user could still force a paid
/// generation on every allowed request. The caller's cooldown (tied to the report's
/// subscription cadence - once a month for Pro, once a week for Advanced) means at
/// most one paid generation per user per report kind per window; everyone else is
/// served the stored report. Monthly and weekly are tracked independently so
/// refreshing one never blocks the other.
/// </summary>
public sealed class AiRefreshThrottle : IAiRefreshThrottle
{
    // Prune once the map is meaningfully larger than one cooldown window's worth of
    // (user, report kind) pairs. Conservative: only entries older than the longest
    // cooldown in use (the monthly one) are pruned, so a still-active weekly entry
    // is never removed early - it just may take a little longer to get swept once
    // it does expire.
    private const int PruneThreshold = 1024;
    private static readonly TimeSpan MaxKnownCooldown = TimeSpan.FromDays(30);

    private readonly ConcurrentDictionary<(Guid UserId, string ReportKind), DateTime> _lastRefreshUtc = new();

    public bool TryAcquire(Guid userId, string reportKind, TimeSpan cooldown)
    {
        var now = DateTime.UtcNow;
        var key = (userId, reportKind);

        if (_lastRefreshUtc.Count > PruneThreshold)
        {
            PruneExpired(now);
        }

        // Loop re-reads on a lost race so two concurrent callers can't both win.
        while (true)
        {
            if (!_lastRefreshUtc.TryGetValue(key, out var last))
            {
                if (_lastRefreshUtc.TryAdd(key, now))
                {
                    return true;
                }

                continue;
            }

            if (now - last >= cooldown)
            {
                if (_lastRefreshUtc.TryUpdate(key, now, last))
                {
                    return true;
                }

                continue;
            }

            return false;
        }
    }

    private void PruneExpired(DateTime now)
    {
        foreach (var (key, last) in _lastRefreshUtc)
        {
            if (now - last >= MaxKnownCooldown)
            {
                _lastRefreshUtc.TryRemove(key, out _);
            }
        }
    }
}
