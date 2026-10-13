using Npgsql;

namespace Silen.Data.Abstractions;

/// <summary>
/// The single dynamic ADO.NET helper every Provider calls to run a database
/// routine. There is no other way to reach PostgreSQL anywhere in this
/// codebase - no ORM, no inline/concatenated SQL, no second helper.
/// </summary>
public interface ISqlExecutor
{
    /// <summary>
    /// Opens a connection, runs <paramref name="procedureName"/> (a dbo function
    /// returning one refcursor per result set) with <paramref name="parameters"/>,
    /// and hands the reader to <paramref name="mapAsync"/> to project into
    /// <typeparamref name="T"/>. The caller advances result sets itself via
    /// reader.NextResultAsync() when a routine returns more than one.
    /// </summary>
    Task<T> QueryAsync<T>(
        string procedureName,
        NpgsqlParameter[] parameters,
        Func<NpgsqlDataReader, Task<T>> mapAsync,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Runs a routine whose result sets (if any) the caller doesn't need, inside
    /// its own transaction.
    /// </summary>
    Task ExecuteAsync(
        string procedureName,
        NpgsqlParameter[] parameters,
        CancellationToken cancellationToken = default);
}
