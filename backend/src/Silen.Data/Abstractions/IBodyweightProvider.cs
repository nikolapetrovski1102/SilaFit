using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IBodyweightProvider
{
    /// <summary>Logs a new entry and returns the two most recent entries (newest first).</summary>
    Task<List<BodyweightEntryModel>> LogAsync(Guid userId, decimal weightKg, CancellationToken cancellationToken = default);

    Task<List<BodyweightEntryModel>> GetLatestAsync(Guid userId, CancellationToken cancellationToken = default);
}
