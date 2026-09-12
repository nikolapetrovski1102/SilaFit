using Microsoft.Data.SqlClient;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

public static class UserProfileRowMapper
{
    public static UserProfileModel MapUserProfile(SqlDataReader reader) => new()
    {
        UserId = reader.GetGuidValue("UserId"),
        Gender = reader.GetNullableString("Gender"),
        AgeYears = reader.IsDBNull(reader.GetOrdinal("AgeYears")) ? null : reader.GetByteValue("AgeYears"),
        HeightCm = reader.GetNullableDecimal("HeightCm"),
        WeightKg = reader.GetNullableDecimal("WeightKg"),
        Goal = reader.GetNullableString("Goal"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc"),
        UpdatedAtUtc = reader.GetDateTimeValue("UpdatedAtUtc")
    };
}
