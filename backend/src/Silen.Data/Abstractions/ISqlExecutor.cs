using Microsoft.Data.SqlClient;

namespace Silen.Data.Abstractions;

/// <summary>
/// The single dynamic ADO.NET helper every Provider calls to run a stored
/// procedure. There is no other way to reach SQL Server anywhere in this
/// codebase - no ORM, no inline/concatenated SQL, no second helper.
/// </summary>
public interface ISqlExecutor
{
    /// <summary>
    /// Opens a connection, runs <paramref name="procedureName"/> as a stored
    /// procedure with <paramref name="parameters"/>, and hands the open
    /// reader to <paramref name="mapAsync"/> to project into <typeparamref name="T"/>.
    /// The caller advances result sets itself via reader.NextResultAsync()
    /// when a procedure returns more than one.
    /// </summary>
    Task<T> QueryAsync<T>(
        string procedureName,
        SqlParameter[] parameters,
        Func<SqlDataReader, Task<T>> mapAsync,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Runs a stored procedure that returns no result set (INSERT/UPDATE-only
    /// procedures), optionally inside its own transaction.
    /// </summary>
    Task ExecuteAsync(
        string procedureName,
        SqlParameter[] parameters,
        CancellationToken cancellationToken = default);
}
