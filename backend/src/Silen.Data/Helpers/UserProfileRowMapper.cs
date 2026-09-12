using Microsoft.Data.SqlClient;
using Silen.Common.Helpers;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

public static class UserProfileRowMapper
{
    /// <summary>Maps a row whose Gender/AgeYears/HeightCm/WeightKg/Goal columns are
    /// AES-256-GCM ciphertext (see UserProfileProvider), decrypting each with <paramref name="key"/>.</summary>
    public static UserProfileModel MapUserProfile(SqlDataReader reader, byte[] key)
    {
        var gender = reader.GetNullableBytes("Gender");
        var ageYears = reader.GetNullableBytes("AgeYears");
        var heightCm = reader.GetNullableBytes("HeightCm");
        var weightKg = reader.GetNullableBytes("WeightKg");
        var goal = reader.GetNullableBytes("Goal");

        return new UserProfileModel
        {
            UserId = reader.GetGuidValue("UserId"),
            Gender = gender is null ? null : FieldCipher.DecryptString(gender, key),
            AgeYears = ageYears is null ? null : (byte)FieldCipher.DecryptInt(ageYears, key),
            HeightCm = heightCm is null ? null : FieldCipher.DecryptDecimal(heightCm, key),
            WeightKg = weightKg is null ? null : FieldCipher.DecryptDecimal(weightKg, key),
            Goal = goal is null ? null : FieldCipher.DecryptString(goal, key),
            CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc"),
            UpdatedAtUtc = reader.GetDateTimeValue("UpdatedAtUtc")
        };
    }
}
