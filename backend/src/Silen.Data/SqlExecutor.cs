using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Silen.Data.Abstractions;

namespace Silen.Data;

/// <inheritdoc cref="ISqlExecutor"/>
public sealed class SqlExecutor : ISqlExecutor
{
    private readonly string _connectionString;

    public SqlExecutor(IConfiguration configuration)
    {
        _connectionString = configuration.GetConnectionString("SilenDb")
            ?? throw new InvalidOperationException("Connection string 'SilenDb' is not configured.");
    }

    public async Task<T> QueryAsync<T>(
        string procedureName,
        SqlParameter[] parameters,
        Func<SqlDataReader, Task<T>> mapAsync,
        CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken).ConfigureAwait(false);

        await using var command = new SqlCommand(procedureName, connection) { CommandType = CommandType.StoredProcedure };
        if (parameters.Length > 0)
        {
            command.Parameters.AddRange(parameters);
        }

        await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
        return await mapAsync(reader).ConfigureAwait(false);
    }

    public async Task ExecuteAsync(
        string procedureName,
        SqlParameter[] parameters,
        CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken).ConfigureAwait(false);

        await using var command = new SqlCommand(procedureName, connection) { CommandType = CommandType.StoredProcedure };
        if (parameters.Length > 0)
        {
            command.Parameters.AddRange(parameters);
        }

        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }
}
