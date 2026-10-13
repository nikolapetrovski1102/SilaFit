using System.Collections.Concurrent;
using System.Text;
using Microsoft.Extensions.Configuration;
using Npgsql;
using Silen.Data.Abstractions;

namespace Silen.Data;

/// <inheritdoc cref="ISqlExecutor"/>
/// <remarks>
/// Every database routine is a PL/pgSQL function in the dbo schema that returns
/// SETOF refcursor, one cursor per result set (see database/functions). A call
/// runs the function inside a transaction, fetches each returned cursor in one
/// batch so the caller sees an ordinary multi-result reader, then commits.
///
/// Providers still name routines and parameters the way they always have
/// ("dbo.usp_WorkoutSession_Complete", "@UserId"); the executor maps them onto the
/// lowercase function and its p_-prefixed arguments, and casts each value to the
/// argument's declared type, read once per function from pg_proc and cached.
/// </remarks>
public sealed class SqlExecutor : ISqlExecutor
{
    private readonly NpgsqlDataSource _dataSource;
    private readonly int _commandTimeoutSeconds;
    private readonly ConcurrentDictionary<string, Task<FunctionSignature>> _signatures = new(StringComparer.Ordinal);

    public SqlExecutor(IConfiguration configuration)
        : this(
            configuration.GetConnectionString("SilenDb")
                ?? throw new InvalidOperationException("Connection string 'SilenDb' is not configured."),
            int.TryParse(configuration["Sql:CommandTimeoutSeconds"], out var timeout) && timeout > 0 ? timeout : 30)
    {
    }

    /// <summary>For callers built outside DI (the CLI tools, MockDataSeeder).</summary>
    public SqlExecutor(string connectionString, int commandTimeoutSeconds = 30)
    {
        _dataSource = NpgsqlDataSource.Create(ApplyConnectionDefaults(connectionString));
        _commandTimeoutSeconds = commandTimeoutSeconds;
    }

    public async Task<T> QueryAsync<T>(
        string procedureName,
        NpgsqlParameter[] parameters,
        Func<NpgsqlDataReader, Task<T>> mapAsync,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken).ConfigureAwait(false);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken).ConfigureAwait(false);

        var cursors = await CallAsync(connection, transaction, procedureName, parameters, cancellationToken).ConfigureAwait(false);

        await using var batch = new NpgsqlBatch(connection, transaction) { Timeout = _commandTimeoutSeconds };
        foreach (var cursor in cursors)
        {
            batch.BatchCommands.Add(new NpgsqlBatchCommand($"FETCH ALL FROM \"{cursor.Replace("\"", "\"\"")}\""));
        }

        // A function that returned no cursor still hands the mapper a (single,
        // empty) result set, the same as a procedure that selected nothing.
        if (batch.BatchCommands.Count == 0)
        {
            batch.BatchCommands.Add(new NpgsqlBatchCommand("SELECT NULL WHERE false"));
        }

        T result;
        await using (var reader = await batch.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false))
        {
            result = await mapAsync(reader).ConfigureAwait(false);
        }

        await transaction.CommitAsync(cancellationToken).ConfigureAwait(false);
        return result;
    }

    public async Task ExecuteAsync(
        string procedureName,
        NpgsqlParameter[] parameters,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(cancellationToken).ConfigureAwait(false);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken).ConfigureAwait(false);

        // Any cursors the function opened close with the transaction.
        await CallAsync(connection, transaction, procedureName, parameters, cancellationToken).ConfigureAwait(false);

        await transaction.CommitAsync(cancellationToken).ConfigureAwait(false);
    }

    private async Task<List<string>> CallAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string procedureName,
        NpgsqlParameter[] parameters,
        CancellationToken cancellationToken)
    {
        var functionName = ToFunctionName(procedureName);
        var signature = await GetSignatureAsync(connection, functionName, cancellationToken).ConfigureAwait(false);

        var sql = new StringBuilder("SELECT * FROM dbo.").Append(functionName).Append('(');
        await using var command = new NpgsqlCommand { Connection = connection, Transaction = transaction, CommandTimeout = _commandTimeoutSeconds };

        for (var i = 0; i < parameters.Length; i++)
        {
            var argumentName = ToArgumentName(parameters[i].ParameterName);
            if (!signature.ArgumentTypes.TryGetValue(argumentName, out var argumentType))
            {
                throw new InvalidOperationException(
                    $"dbo.{functionName} has no argument '{argumentName}' (from parameter '{parameters[i].ParameterName}').");
            }

            if (i > 0)
            {
                sql.Append(", ");
            }

            sql.Append(argumentName).Append(" => $").Append(i + 1).Append("::").Append(argumentType);
            command.Parameters.Add(new NpgsqlParameter { Value = NormalizeValue(parameters[i].Value) });
        }

        command.CommandText = sql.Append(')').ToString();

        var cursors = new List<string>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
        while (await reader.ReadAsync(cancellationToken).ConfigureAwait(false))
        {
            if (!reader.IsDBNull(0))
            {
                cursors.Add(reader.GetString(0));
            }
        }

        return cursors;
    }

    private Task<FunctionSignature> GetSignatureAsync(
        NpgsqlConnection connection, string functionName, CancellationToken cancellationToken)
    {
        var pending = _signatures.GetOrAdd(functionName, name => LoadSignatureAsync(connection, name, cancellationToken));

        // A failed lookup (cancelled request, missing function) is not cached, so the
        // next call tries again instead of failing forever.
        if (pending.IsFaulted || pending.IsCanceled)
        {
            _signatures.TryRemove(new KeyValuePair<string, Task<FunctionSignature>>(functionName, pending));
        }

        return pending;
    }

    private static async Task<FunctionSignature> LoadSignatureAsync(
        NpgsqlConnection connection, string functionName, CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT a.name, format_type(a.type, NULL)
            FROM pg_proc p
            CROSS JOIN LATERAL unnest(p.proargnames, p.proargtypes::oid[]) AS a(name, type)
            WHERE p.pronamespace = 'dbo'::regnamespace AND p.proname = $1
            """,
            connection);
        command.Parameters.Add(new NpgsqlParameter { Value = functionName });

        var argumentTypes = new Dictionary<string, string>(StringComparer.Ordinal);
        var found = false;

        // A function with no arguments has a NULL proargnames and so returns no rows
        // here; the existence check below tells that apart from a missing function.
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false))
        {
            while (await reader.ReadAsync(cancellationToken).ConfigureAwait(false))
            {
                found = true;
                argumentTypes[reader.GetString(0)] = reader.GetString(1);
            }
        }

        if (!found)
        {
            await using var exists = new NpgsqlCommand(
                "SELECT 1 FROM pg_proc WHERE pronamespace = 'dbo'::regnamespace AND proname = $1", connection);
            exists.Parameters.Add(new NpgsqlParameter { Value = functionName });
            if (await exists.ExecuteScalarAsync(cancellationToken).ConfigureAwait(false) is null)
            {
                throw new InvalidOperationException($"Database function dbo.{functionName} does not exist.");
            }
        }

        return new FunctionSignature(argumentTypes);
    }

    /// <summary>"dbo.usp_WorkoutSession_Complete" → "usp_workoutsession_complete".</summary>
    private static string ToFunctionName(string procedureName)
    {
        var name = procedureName.StartsWith("dbo.", StringComparison.OrdinalIgnoreCase)
            ? procedureName[4..]
            : procedureName;
        return name.ToLowerInvariant();
    }

    /// <summary>"@UserId" → "p_userid".</summary>
    private static string ToArgumentName(string parameterName) =>
        "p_" + parameterName.TrimStart('@').ToLowerInvariant();

    /// <summary>
    /// Brings CLR values in line with the casts in the call: every timestamp column is
    /// "without time zone" holding UTC, so a Utc-kind DateTime is sent as a plain one
    /// (Npgsql would otherwise send timestamptz); enums go as their number, and byte
    /// (SQL Server tinyint) as a smallint, which PostgreSQL has instead.
    /// </summary>
    private static object NormalizeValue(object? value) => value switch
    {
        null => DBNull.Value,
        DateTime dateTime => DateTime.SpecifyKind(dateTime, DateTimeKind.Unspecified),
        Enum enumValue => Convert.ToInt32(enumValue),
        byte byteValue => (short)byteValue,
        sbyte sbyteValue => (short)sbyteValue,
        _ => value
    };

    /// <summary>
    /// Fills in pooling defaults only where the operator hasn't specified them, so a
    /// connection string in config stays the source of truth. Timeout keeps a dead
    /// database from hanging a request for the driver default; Minimum Pool Size keeps
    /// a few warm connections so bursts don't pay open cost every time; auto-prepare
    /// lets the handful of hot calls skip re-planning.
    /// </summary>
    private static string ApplyConnectionDefaults(string connectionString)
    {
        var builder = new NpgsqlConnectionStringBuilder(connectionString);

        if (!builder.ContainsKey("Timeout"))
        {
            builder.Timeout = 10;
        }

        if (!builder.ContainsKey("Minimum Pool Size"))
        {
            builder.MinPoolSize = 2;
        }

        if (!builder.ContainsKey("Maximum Pool Size"))
        {
            builder.MaxPoolSize = 100;
        }

        if (!builder.ContainsKey("Max Auto Prepare"))
        {
            builder.MaxAutoPrepare = 50;
        }

        if (!builder.ContainsKey("Search Path"))
        {
            builder.SearchPath = "dbo,public";
        }

        return builder.ConnectionString;
    }

    private sealed record FunctionSignature(Dictionary<string, string> ArgumentTypes);
}
