using Npgsql;

namespace Silen.Data.Helpers;

/// <summary>
/// Outside helper for building <see cref="NpgsqlParameter"/> values, handling
/// the null-to-DBNull conversion in one shared place instead of every
/// Provider repeating it (or reaching for a private method to do it). The name
/// keeps the "@Name" form; <see cref="SqlExecutor"/> maps it to the function's
/// p_name argument.
/// </summary>
public static class SqlParameterBuilder
{
    public static NpgsqlParameter Create(string name, object? value) =>
        new(name, value ?? DBNull.Value);
}
