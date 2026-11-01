using Silen.Common.Contracts;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Common.Helpers;

namespace Silen.Services.Implementations;

/// <summary>
/// Every app launch asks for the splash lines, anonymously, so the active set is
/// kept in memory for a few minutes instead of hitting the database each time.
/// An edit in the database shows up once the window runs out.
/// </summary>
public sealed class MotivationalQuoteService(
    IMotivationalQuotesProvider quotesProvider,
    TimeProvider timeProvider) : IMotivationalQuoteService
{
    private static readonly TimeSpan CacheWindow = TimeSpan.FromMinutes(10);
    private static (List<MotivationalQuoteModel> Quotes, DateTimeOffset ExpiresAt)? _cache;

    public Task<ServiceResult<List<MotivationalQuoteModel>>> GetActiveAsync(CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var now = timeProvider.GetUtcNow();
            var cached = _cache;
            if (cached is { } hit && hit.ExpiresAt > now)
            {
                return hit.Quotes;
            }

            var quotes = await quotesProvider.GetActiveAsync(cancellationToken);
            _cache = (quotes, now + CacheWindow);
            return quotes;
        });
}
