using Npgsql;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

/// <inheritdoc cref="IMotivationalQuotesProvider"/>
public sealed class MotivationalQuotesProvider(ISqlExecutor sqlExecutor) : IMotivationalQuotesProvider
{
    public Task<List<MotivationalQuoteModel>> GetActiveAsync(CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_MotivationalQuotes_GetActive",
            [],
            reader => SqlResultSetReader.ReadListAsync(reader, MapQuote, cancellationToken),
            cancellationToken);

    private static MotivationalQuoteModel MapQuote(NpgsqlDataReader reader) => new()
    {
        QuoteId = reader.GetGuidValue("QuoteId"),
        Text = reader.GetStringValue("Text"),
        Author = reader.GetNullableString("Author"),
        SortOrder = reader.GetInt32Value("SortOrder")
    };
}
