using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>Motivational lines for the splash screen (MotivationalQuotes.sql).</summary>
public interface IMotivationalQuotesProvider
{
    Task<List<MotivationalQuoteModel>> GetActiveAsync(CancellationToken cancellationToken = default);
}
