using System.Diagnostics;
using System.Globalization;
using System.Text;
using Microsoft.Data.SqlClient;
using Npgsql;
using NpgsqlTypes;

// One-off move of SilenDb from SQL Server to PostgreSQL.
//
// The target must already hold the bare tables (database/apply.sh --until=0001)
// with no indexes, checks or foreign keys yet, so rows load in any order at COPY
// speed. Constraints, functions and grants follow with a plain database/apply.sh.
//
// Usage:
//   SOURCE_CONNECTION_STRING="Server=...;Database=SilenDb;..." \
//   TARGET_CONNECTION_STRING="Host=...;Database=silendb;..." \
//     dotnet run --project backend/src/Silen.Tools.MigrateToPostgres -- copy
//
//   copy    streams every dbo table across with binary COPY, then moves the
//           identity sequences past the copied ids. Refuses non-empty targets.
//   verify  re-reads both sides and compares row counts plus an order-independent
//           fingerprint of every column's values. Exits 1 on any mismatch.
//
// Encrypted columns move as opaque bytes, so ENCRYPTION_MASTER_KEY is not needed.

var mode = args.FirstOrDefault()?.ToLowerInvariant();
if (mode is not ("copy" or "verify"))
{
    Console.Error.WriteLine("Usage: Silen.Tools.MigrateToPostgres copy|verify");
    return 2;
}

var sourceConnectionString = Required("SOURCE_CONNECTION_STRING");
var targetConnectionString = Required("TARGET_CONNECTION_STRING");

await using var source = new SqlConnection(sourceConnectionString);
await using var target = new NpgsqlConnection(targetConnectionString);
await source.OpenAsync();
await target.OpenAsync();

var tables = await ReadTargetTablesAsync(target);
var sourceTables = await ReadSourceTablesAsync(source);
var missing = sourceTables.Where(name => !tables.ContainsKey(name.ToLowerInvariant())).ToList();
if (missing.Count > 0)
{
    Console.Error.WriteLine($"Source tables with no target table: {string.Join(", ", missing)}");
    return 1;
}

return mode == "copy"
    ? await CopyAsync(source, target, tables)
    : await VerifyAsync(source, target, tables);

static async Task<int> CopyAsync(SqlConnection source, NpgsqlConnection target, Dictionary<string, List<TargetColumn>> tables)
{
    foreach (var table in tables.Keys)
    {
        await using var probe = new NpgsqlCommand($"SELECT EXISTS (SELECT 1 FROM dbo.{table})", target);
        if (await probe.ExecuteScalarAsync() is true)
        {
            Console.Error.WriteLine($"dbo.{table} already has rows; copy expects an empty target.");
            return 1;
        }
    }

    var total = Stopwatch.StartNew();
    foreach (var (table, columns) in tables)
    {
        var watch = Stopwatch.StartNew();
        var names = string.Join(", ", columns.Select(column => column.Name));
        await using var read = new SqlCommand(
            $"SELECT {string.Join(", ", columns.Select(column => $"[{column.Name}]"))} FROM dbo.[{table}]", source)
        { CommandTimeout = 0 };
        await using var reader = await read.ExecuteReaderAsync(System.Data.CommandBehavior.SequentialAccess);

        long rows = 0, strippedNuls = 0;
        await using (var import = await target.BeginBinaryImportAsync($"COPY dbo.{table} ({names}) FROM STDIN (FORMAT BINARY)"))
        {
            import.Timeout = TimeSpan.Zero;
            while (await reader.ReadAsync())
            {
                await import.StartRowAsync();
                for (var i = 0; i < columns.Count; i++)
                {
                    var value = reader.GetValue(i);
                    if (value is DBNull)
                    {
                        await import.WriteNullAsync();
                        continue;
                    }
                    if (value is string text && text.Contains('\0'))
                    {
                        // PostgreSQL text cannot hold U+0000; SQL Server can.
                        value = text.Replace("\0", string.Empty);
                        strippedNuls++;
                    }
                    await import.WriteAsync(ToTarget(value, columns[i].Type), columns[i].DbType);
                }
                rows++;
            }
            await import.CompleteAsync();
        }

        Console.WriteLine($"{table,-40} {rows,12:N0} rows  {watch.Elapsed.TotalSeconds,7:N1}s"
            + (strippedNuls > 0 ? $"  ({strippedNuls} values had NUL characters removed)" : string.Empty));
    }

    await using (var sequences = new NpgsqlCommand("""
        SELECT c.table_name, c.column_name
        FROM information_schema.columns c
        WHERE c.table_schema = 'dbo' AND c.is_identity = 'YES'
        """, target))
    await using (var reader = await sequences.ExecuteReaderAsync())
    {
        var identities = new List<(string Table, string Column)>();
        while (await reader.ReadAsync()) identities.Add((reader.GetString(0), reader.GetString(1)));
        await reader.DisposeAsync();
        foreach (var (table, column) in identities)
        {
            await using var reset = new NpgsqlCommand(
                $"SELECT setval(pg_get_serial_sequence('dbo.{table}', '{column}'), coalesce(max({column}), 0) + 1, false) FROM dbo.{table}",
                target);
            Console.WriteLine($"identity dbo.{table}.{column} -> next {await reset.ExecuteScalarAsync()}");
        }
    }

    Console.WriteLine($"Copied {tables.Count} tables in {total.Elapsed.TotalMinutes:N1} min.");
    return 0;
}

static async Task<int> VerifyAsync(SqlConnection source, NpgsqlConnection target, Dictionary<string, List<TargetColumn>> tables)
{
    var mismatches = 0;
    foreach (var (table, columns) in tables)
    {
        var select = string.Join(", ", columns.Select(column => column.Name));
        await using var read = new SqlCommand(
            $"SELECT {string.Join(", ", columns.Select(column => $"[{column.Name}]"))} FROM dbo.[{table}]", source)
        { CommandTimeout = 0 };
        var expected = await FingerprintAsync(await read.ExecuteReaderAsync(System.Data.CommandBehavior.SequentialAccess), columns);
        await using var readTarget = new NpgsqlCommand($"SELECT {select} FROM dbo.{table}", target) { CommandTimeout = 0 };
        var actual = await FingerprintAsync(await readTarget.ExecuteReaderAsync(), columns);

        var bad = new List<string>();
        if (expected.Rows != actual.Rows) bad.Add($"rows {expected.Rows} vs {actual.Rows}");
        for (var i = 0; i < columns.Count; i++)
        {
            if (expected.Columns[i] != actual.Columns[i]) bad.Add(columns[i].Name);
        }

        Console.WriteLine($"{table,-40} {expected.Rows,12:N0} rows  " + (bad.Count == 0 ? "OK" : "MISMATCH: " + string.Join(", ", bad)));
        if (bad.Count > 0) mismatches++;
    }

    Console.WriteLine(mismatches == 0 ? $"All {tables.Count} tables match." : $"{mismatches} table(s) differ.");
    return mismatches == 0 ? 0 : 1;
}

static async Task<(long Rows, (long Count, ulong Sum)[] Columns)> FingerprintAsync(System.Data.Common.DbDataReader reader, List<TargetColumn> columns)
{
    await using var _ = reader;
    var sums = new (long Count, ulong Sum)[columns.Count];
    long rows = 0;
    while (await reader.ReadAsync())
    {
        for (var i = 0; i < columns.Count; i++)
        {
            var value = reader.GetValue(i);
            if (value is DBNull) continue;
            sums[i].Count++;
            sums[i].Sum += Hash(Canonical(ToTarget(value is string text ? text.Replace("\0", string.Empty) : value, columns[i].Type)));
        }
        rows++;
    }
    return (rows, sums);
}

// Converts a SQL Server value to what the PostgreSQL column stores, and normalizes
// PostgreSQL values to the same shape so fingerprints from both sides line up.
static object ToTarget(object value, string type) => type switch
{
    "smallint" => Convert.ToInt16(value, CultureInfo.InvariantCulture),
    "integer" => Convert.ToInt32(value, CultureInfo.InvariantCulture),
    "bigint" => Convert.ToInt64(value, CultureInfo.InvariantCulture),
    "date" => value is DateOnly date ? date : DateOnly.FromDateTime((DateTime)value),
    "time without time zone" => value is TimeOnly time ? time.ToTimeSpan() : (TimeSpan)value,
    // timestamp keeps microseconds; datetime2(7) rounds the same way PostgreSQL does.
    "timestamp without time zone" => new DateTime(
        (long)Math.Round(((DateTime)value).Ticks / 10.0, MidpointRounding.ToEven) * 10, DateTimeKind.Unspecified),
    _ => value
};

static byte[] Canonical(object value) => value switch
{
    byte[] bytes => bytes,
    string text => Encoding.UTF8.GetBytes(text),
    Guid guid => guid.ToByteArray(),
    bool flag => [flag ? (byte)1 : (byte)0],
    decimal number => Encoding.ASCII.GetBytes(number.ToString("G29", CultureInfo.InvariantCulture)),
    DateTime moment => BitConverter.GetBytes(moment.Ticks),
    DateOnly date => BitConverter.GetBytes(date.DayNumber),
    TimeSpan span => BitConverter.GetBytes(span.Ticks),
    short or int or long => BitConverter.GetBytes(Convert.ToInt64(value, CultureInfo.InvariantCulture)),
    _ => throw new InvalidOperationException($"No fingerprint for {value.GetType()}")
};

// FNV-1a; summed per column so row order does not matter.
static ulong Hash(byte[] bytes)
{
    var hash = 14695981039346656037UL;
    foreach (var b in bytes) hash = (hash ^ b) * 1099511628211UL;
    return hash;
}

static async Task<Dictionary<string, List<TargetColumn>>> ReadTargetTablesAsync(NpgsqlConnection target)
{
    await using var command = new NpgsqlCommand("""
        SELECT c.table_name, c.column_name, c.data_type
        FROM information_schema.columns c
        JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name
        WHERE c.table_schema = 'dbo' AND t.table_type = 'BASE TABLE' AND c.is_generated = 'NEVER'
        ORDER BY c.table_name, c.ordinal_position
        """, target);
    await using var reader = await command.ExecuteReaderAsync();
    var tables = new Dictionary<string, List<TargetColumn>>();
    while (await reader.ReadAsync())
    {
        var type = reader.GetString(2);
        if (!tables.TryGetValue(reader.GetString(0), out var columns))
            tables[reader.GetString(0)] = columns = [];
        columns.Add(new TargetColumn(reader.GetString(1), type, type switch
        {
            "uuid" => NpgsqlDbType.Uuid,
            "character varying" => NpgsqlDbType.Varchar,
            "text" => NpgsqlDbType.Text,
            "timestamp without time zone" => NpgsqlDbType.Timestamp,
            "date" => NpgsqlDbType.Date,
            "time without time zone" => NpgsqlDbType.Time,
            "bytea" => NpgsqlDbType.Bytea,
            "boolean" => NpgsqlDbType.Boolean,
            "smallint" => NpgsqlDbType.Smallint,
            "integer" => NpgsqlDbType.Integer,
            "bigint" => NpgsqlDbType.Bigint,
            "numeric" => NpgsqlDbType.Numeric,
            _ => throw new InvalidOperationException($"Unmapped type {type} on {reader.GetString(0)}.{reader.GetString(1)}")
        }));
    }
    if (tables.Count == 0) throw new InvalidOperationException("Target has no dbo tables. Run database/apply.sh --until=0001 first.");
    return tables;
}

static async Task<List<string>> ReadSourceTablesAsync(SqlConnection source)
{
    await using var command = new SqlCommand("SELECT name FROM sys.tables WHERE schema_id = SCHEMA_ID('dbo') ORDER BY name", source);
    await using var reader = await command.ExecuteReaderAsync();
    var names = new List<string>();
    while (await reader.ReadAsync()) names.Add(reader.GetString(0));
    return names;
}

static string Required(string name) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value
        : throw new InvalidOperationException($"{name} is not set.");

internal sealed record TargetColumn(string Name, string Type, NpgsqlDbType DbType);
