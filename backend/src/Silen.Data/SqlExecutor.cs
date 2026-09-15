using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Silen.Data.Abstractions;

namespace Silen.Data;

/// <inheritdoc cref="ISqlExecutor"/>
public sealed class SqlExecutor : ISqlExecutor
{
    private readonly string _connectionString;
    private readonly int _commandTimeoutSeconds;

    public SqlExecutor(IConfiguration configuration)
    {
        var configured = configuration.GetConnectionString("SilenDb")
            ?? throw new InvalidOperationException("Connection string 'SilenDb' is not configured.");

        _connectionString = ApplyConnectionDefaults(configured);
        _commandTimeoutSeconds = int.TryParse(configuration["Sql:CommandTimeoutSeconds"], out var timeout) && timeout > 0
            ? timeout
            : 30;
    }

    public async Task<T> QueryAsync<T>(
        string procedureName,
        SqlParameter[] parameters,
        Func<SqlDataReader, Task<T>> mapAsync,
        CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken).ConfigureAwait(false);

        await using var command = new SqlCommand(procedureName, connection)
        {
            CommandType = CommandType.StoredProcedure,
            CommandTimeout = _commandTimeoutSeconds
        };
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

        await using var command = new SqlCommand(procedureName, connection)
        {
            CommandType = CommandType.StoredProcedure,
            CommandTimeout = _commandTimeoutSeconds
        };
        if (parameters.Length > 0)
        {
            command.Parameters.AddRange(parameters);
        }

        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    /// <summary>
    /// Fills in pooling defaults only where the operator hasn't specified them, so a
    /// connection string in config stays the source of truth. Connect Timeout keeps a
    /// dead SQL Server from hanging a request for the driver default; Min Pool Size
    /// keeps a few warm connections so bursts don't pay open cost every time.
    /// </summary>
    private static string ApplyConnectionDefaults(string connectionString)
    {
        var builder = new SqlConnectionStringBuilder(connectionString);

        if (!builder.ContainsKey("Connect Timeout"))
        {
            builder.ConnectTimeout = 10;
        }

        if (!builder.ContainsKey("Min Pool Size"))
        {
            builder.MinPoolSize = 2;
        }

        if (!builder.ContainsKey("Max Pool Size"))
        {
            builder.MaxPoolSize = 100;
        }

        return builder.ConnectionString;
    }
}
