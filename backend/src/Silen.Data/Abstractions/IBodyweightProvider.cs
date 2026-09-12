using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IBodyweightProvider
{
    /// <summary>Logs a new entry and returns the two most recent entries (newest first).</summary>
    Task<List<BodyweightEntryModel>> LogAsync(Guid userId, decimal weightKg, CancellationToken cancellationToken = default);

    Task<List<BodyweightEntryModel>> GetLatestAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Entries in [fromDateUtc, toDateUtc], oldest first. Used by AnalyticsProvider to
    /// derive start/end weight now that WeightKg can no longer be aggregated in T-SQL.</summary>
    Task<List<BodyweightEntryModel>> GetInRangeAsync(Guid userId, DateOnly fromDateUtc, DateOnly toDateUtc, CancellationToken cancellationToken = default);
}
