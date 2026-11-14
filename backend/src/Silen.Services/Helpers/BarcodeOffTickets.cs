using System.Collections.Concurrent;

namespace Silen.Services.Helpers;

/// <summary>Short-lived permits for the on-device Open Food Facts path. A barcode lookup
/// that misses the catalog (and has already passed the Pro / trial gate) issues one; the
/// app then asks OFF itself and posts the product back, which spends it. So the save
/// endpoint can't be used to skip the gate, or to write products nobody scanned.
/// In-process: the API runs as a single instance, and a lost ticket (restart) only means
/// the product isn't saved this time - the user still gets the "add it" form.</summary>
public sealed class BarcodeOffTickets(TimeProvider timeProvider)
{
    /// <summary>Long enough for a slow phone network to reach OFF and back.</summary>
    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(3);

    /// <summary>Safety cap: well beyond 15 scans a minute across every active user.</summary>
    private const int MaxTickets = 50_000;

    private readonly ConcurrentDictionary<(Guid UserId, string Barcode), DateTimeOffset> tickets = new();

    public void Issue(Guid userId, string barcode)
    {
        var now = timeProvider.GetUtcNow();
        if (tickets.Count >= MaxTickets)
        {
            Prune(now);
        }

        tickets[(userId, barcode)] = now + Lifetime;
    }

    /// <summary>True (and the ticket is gone) when this user was issued one for this
    /// barcode that hasn't expired.</summary>
    public bool TryConsume(Guid userId, string barcode) =>
        tickets.TryRemove((userId, barcode), out var expiresAt) && expiresAt > timeProvider.GetUtcNow();

    private void Prune(DateTimeOffset now)
    {
        foreach (var (key, expiresAt) in tickets)
        {
            if (expiresAt <= now)
            {
                tickets.TryRemove(key, out _);
            }
        }
    }
}
