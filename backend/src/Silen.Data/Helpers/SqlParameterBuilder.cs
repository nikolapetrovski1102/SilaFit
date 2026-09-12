using Microsoft.Data.SqlClient;

namespace Silen.Data.Helpers;

/// <summary>
/// Outside helper for building <see cref="SqlParameter"/> values, handling
/// the null-to-DBNull conversion in one shared place instead of every
/// Provider repeating it (or reaching for a private method to do it).
/// </summary>
public static class SqlParameterBuilder
{
    public static SqlParameter Create(string name, object? value) =>
        new(name, value ?? DBNull.Value);
}
