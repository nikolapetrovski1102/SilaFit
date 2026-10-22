using Npgsql;

namespace Silen.Data.Helpers;

/// <summary>
/// Outside helper (extension methods, not private members) that every
/// Provider uses to read columns off a <see cref="NpgsqlDataReader"/> without
/// repeating null-checking/ordinal-lookup boilerplate.
///
/// The integer readers convert rather than demand an exact column type: PostgreSQL
/// has no tinyint (those columns are smallint now) and some aggregates come back
/// wider than the mapper asks for, so a mapper that reads a byte or an int keeps
/// working whichever integer type the function returns.
/// </summary>
public static class NpgsqlDataReaderExtensions
{
    public static Guid GetGuidValue(this NpgsqlDataReader reader, string column) =>
        reader.GetGuid(reader.GetOrdinal(column));

    public static Guid? GetNullableGuid(this NpgsqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetGuid(ordinal);
    }

    public static string GetStringValue(this NpgsqlDataReader reader, string column) =>
        reader.GetString(reader.GetOrdinal(column));

    public static string? GetNullableString(this NpgsqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);
    }

    public static int GetInt32Value(this NpgsqlDataReader reader, string column) =>
        Convert.ToInt32(reader.GetValue(reader.GetOrdinal(column)));

    public static int? GetNullableInt32(this NpgsqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : Convert.ToInt32(reader.GetValue(ordinal));
    }

    public static short GetInt16Value(this NpgsqlDataReader reader, string column) =>
        Convert.ToInt16(reader.GetValue(reader.GetOrdinal(column)));

    public static short? GetNullableInt16(this NpgsqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : Convert.ToInt16(reader.GetValue(ordinal));
    }

    public static byte GetByteValue(this NpgsqlDataReader reader, string column) =>
        Convert.ToByte(reader.GetValue(reader.GetOrdinal(column)));

    public static byte? GetNullableByte(this NpgsqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : Convert.ToByte(reader.GetValue(ordinal));
    }

    public static decimal GetDecimalValue(this NpgsqlDataReader reader, string column) =>
        Convert.ToDecimal(reader.GetValue(reader.GetOrdinal(column)));

    public static decimal? GetNullableDecimal(this NpgsqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : Convert.ToDecimal(reader.GetValue(ordinal));
    }

    public static bool GetBoolValue(this NpgsqlDataReader reader, string column) =>
        reader.GetBoolean(reader.GetOrdinal(column));

    public static bool? GetNullableBool(this NpgsqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetBoolean(ordinal);
    }

    public static DateTime GetDateTimeValue(this NpgsqlDataReader reader, string column) =>
        reader.GetDateTime(reader.GetOrdinal(column));

    public static DateTime? GetNullableDateTime(this NpgsqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetDateTime(ordinal);
    }

    public static TimeSpan GetTimeSpanValue(this NpgsqlDataReader reader, string column) =>
        reader.GetTimeSpan(reader.GetOrdinal(column));

    /// <summary>A timestamp[] column; NULL (e.g. an empty array_agg) reads as an empty list.</summary>
    public static IReadOnlyList<DateTime> GetDateTimeArray(this NpgsqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? [] : reader.GetFieldValue<DateTime[]>(ordinal);
    }

    public static byte[]? GetNullableBytes(this NpgsqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        if (reader.IsDBNull(ordinal))
        {
            return null;
        }

        var length = (int)reader.GetBytes(ordinal, 0, null, 0, 0);
        var buffer = new byte[length];
        reader.GetBytes(ordinal, 0, buffer, 0, length);
        return buffer;
    }

    public static byte[] GetBytesValue(this NpgsqlDataReader reader, string column) =>
        GetNullableBytes(reader, column) ?? throw new InvalidOperationException($"Column '{column}' was unexpectedly NULL.");
}
