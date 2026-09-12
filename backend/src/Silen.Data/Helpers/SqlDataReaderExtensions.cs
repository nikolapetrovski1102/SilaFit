using Microsoft.Data.SqlClient;

namespace Silen.Data.Helpers;

/// <summary>
/// Outside helper (extension methods, not private members) that every
/// Provider uses to read columns off a <see cref="SqlDataReader"/> without
/// repeating null-checking/ordinal-lookup boilerplate.
/// </summary>
public static class SqlDataReaderExtensions
{
    public static Guid GetGuidValue(this SqlDataReader reader, string column) =>
        reader.GetGuid(reader.GetOrdinal(column));

    public static Guid? GetNullableGuid(this SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetGuid(ordinal);
    }

    public static string GetStringValue(this SqlDataReader reader, string column) =>
        reader.GetString(reader.GetOrdinal(column));

    public static string? GetNullableString(this SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);
    }

    public static int GetInt32Value(this SqlDataReader reader, string column) =>
        reader.GetInt32(reader.GetOrdinal(column));

    public static int? GetNullableInt32(this SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetInt32(ordinal);
    }

    public static short GetInt16Value(this SqlDataReader reader, string column) =>
        reader.GetInt16(reader.GetOrdinal(column));

    public static short? GetNullableInt16(this SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetInt16(ordinal);
    }

    public static byte GetByteValue(this SqlDataReader reader, string column) =>
        reader.GetByte(reader.GetOrdinal(column));

    public static decimal GetDecimalValue(this SqlDataReader reader, string column) =>
        reader.GetDecimal(reader.GetOrdinal(column));

    public static decimal? GetNullableDecimal(this SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetDecimal(ordinal);
    }

    public static bool GetBoolValue(this SqlDataReader reader, string column) =>
        reader.GetBoolean(reader.GetOrdinal(column));

    public static bool? GetNullableBool(this SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetBoolean(ordinal);
    }

    public static DateTime GetDateTimeValue(this SqlDataReader reader, string column) =>
        reader.GetDateTime(reader.GetOrdinal(column));

    public static DateTime? GetNullableDateTime(this SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetDateTime(ordinal);
    }

    public static TimeSpan GetTimeSpanValue(this SqlDataReader reader, string column) =>
        reader.GetTimeSpan(reader.GetOrdinal(column));

    public static byte[]? GetNullableBytes(this SqlDataReader reader, string column)
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
}
