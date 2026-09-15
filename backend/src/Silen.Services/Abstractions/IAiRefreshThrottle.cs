namespace Silen.Services.Abstractions;

/// <summary>
/// Per-user, per-report-kind cooldown around the billable OpenRouter call behind
/// "force refresh". Kept as an interface so the analytics service can be reasoned
/// about without the clock, and registered as a singleton so the window survives
/// across requests.
/// </summary>
public interface IAiRefreshThrottle
{
    /// <summary>
    /// Returns true when a fresh AI generation is allowed for this user and report
    /// kind (e.g. "Monthly" vs "Weekly"), and false while that user is still inside
    /// the cooldown window for that report kind. The first caller in a window wins;
    /// the rest are told to fall back to the cached report. The caller supplies the
    /// cooldown so it can match the report's subscription cadence (once a month for
    /// the Pro monthly report, once a week for the Advanced weekly report).
    /// </summary>
    bool TryAcquire(Guid userId, string reportKind, TimeSpan cooldown);
}
