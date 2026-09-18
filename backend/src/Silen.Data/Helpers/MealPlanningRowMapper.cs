using Microsoft.Data.SqlClient;
using Silen.Common.Helpers;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

public static class MealPlanningRowMapper
{
    /// <summary>TargetCalories/TargetProteinG/TargetCarbsG/TargetFatsG are AES-256-GCM
    /// ciphertext (see MealPlanningProvider) - decrypted here with <paramref name="key"/>.</summary>
    public static UserNutritionTargetsModel MapNutritionTargets(SqlDataReader reader, byte[] key) => new()
    {
        UserId = reader.GetGuidValue("UserId"),
        TargetCalories = (short)FieldCipher.DecryptInt(reader.GetBytesValue("TargetCalories"), key),
        TargetProteinG = (short)FieldCipher.DecryptInt(reader.GetBytesValue("TargetProteinG"), key),
        TargetCarbsG = (short)FieldCipher.DecryptInt(reader.GetBytesValue("TargetCarbsG"), key),
        TargetFatsG = (short)FieldCipher.DecryptInt(reader.GetBytesValue("TargetFatsG"), key),
        IsManualOverride = reader.GetBoolValue("IsManualOverride"),
        UpdatedAtUtc = reader.GetDateTimeValue("UpdatedAtUtc")
    };

    /// <summary>Title/CaloriesKcal/ProteinG/CarbsG/FatsG are AES-256-GCM ciphertext
    /// (see MealPlanningProvider) - decrypted here with <paramref name="key"/>.</summary>
    public static MealLogModel MapMealLog(SqlDataReader reader, byte[] key) => new()
    {
        MealLogId = reader.GetGuidValue("MealLogId"),
        UserId = reader.GetGuidValue("UserId"),
        LogDateUtc = DateOnly.FromDateTime(reader.GetDateTimeValue("LogDateUtc")),
        MealType = reader.GetStringValue("MealType"),
        Title = FieldCipher.DecryptString(reader.GetBytesValue("Title"), key),
        CaloriesKcal = (short)FieldCipher.DecryptInt(reader.GetBytesValue("CaloriesKcal"), key),
        ProteinG = (short)FieldCipher.DecryptInt(reader.GetBytesValue("ProteinG"), key),
        CarbsG = (short)FieldCipher.DecryptInt(reader.GetBytesValue("CarbsG"), key),
        FatsG = (short)FieldCipher.DecryptInt(reader.GetBytesValue("FatsG"), key),
        Status = reader.GetStringValue("Status"),
        PlannedLocalTime = reader.IsDBNull(reader.GetOrdinal("PlannedLocalTime")) ? null : reader.GetTimeSpanValue("PlannedLocalTime"),
        LoggedAtUtc = reader.GetNullableDateTime("LoggedAtUtc"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc")
    };

    /// <summary>System-authored content (not user data) - stays plaintext.</summary>
    public static MealSuggestionModel MapMealSuggestion(SqlDataReader reader) => new()
    {
        MealSuggestionId = reader.GetGuidValue("MealSuggestionId"),
        Title = reader.GetStringValue("Title"),
        MealType = reader.GetStringValue("MealType"),
        Description = reader.GetNullableString("Description"),
        CaloriesKcal = reader.GetInt16Value("CaloriesKcal"),
        ProteinG = reader.GetInt16Value("ProteinG"),
        CarbsG = reader.GetInt16Value("CarbsG"),
        FatsG = reader.GetInt16Value("FatsG"),
        HasIngredients = reader.GetBoolValue("HasIngredients"),
        SuggestedMonth = reader.IsDBNull(reader.GetOrdinal("SuggestedMonth")) ? null : reader.GetByteValue("SuggestedMonth"),
        IsSystemDefault = reader.GetBoolValue("IsSystemDefault"),
        SortOrder = reader.GetInt32Value("SortOrder")
    };
}
