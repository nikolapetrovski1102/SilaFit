using Microsoft.Data.SqlClient;

namespace Silen.Data.Helpers;

/// <summary>
/// Outside helper that drains a result set into a list, or reads a single
/// row, using a caller-supplied row mapper. Providers call this instead of
/// writing their own private read-loop method.
/// </summary>
public static class SqlResultSetReader
{
    public static async Task<List<T>> ReadListAsync<T>(
        SqlDataReader reader,
        Func<SqlDataReader, T> map,
        CancellationToken cancellationToken = default)
    {
        var results = new List<T>();
        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(map(reader));
        }

        return results;
    }

    public static async Task<T?> ReadSingleOrDefaultAsync<T>(
        SqlDataReader reader,
        Func<SqlDataReader, T> map,
        CancellationToken cancellationToken = default)
        where T : class
    {
        return await reader.ReadAsync(cancellationToken) ? map(reader) : null;
    }

    /// <summary>Reads exactly one row and projects a single value from it (e.g. an output Guid/count).</summary>
    public static async Task<T> ReadScalarRowAsync<T>(
        SqlDataReader reader,
        Func<SqlDataReader, T> map,
        CancellationToken cancellationToken = default)
    {
        await reader.ReadAsync(cancellationToken);
        return map(reader);
    }
}
