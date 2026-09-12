using Microsoft.Data.SqlClient;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

public static class MealPlanningRowMapper
{
    public static UserNutritionTargetsModel MapNutritionTargets(SqlDataReader reader) => new()
    {
        UserId = reader.GetGuidValue("UserId"),
        TargetCalories = reader.GetInt16Value("TargetCalories"),
        TargetProteinG = reader.GetInt16Value("TargetProteinG"),
        TargetCarbsG = reader.GetInt16Value("TargetCarbsG"),
        TargetFatsG = reader.GetInt16Value("TargetFatsG"),
        UpdatedAtUtc = reader.GetDateTimeValue("UpdatedAtUtc")
    };

    public static MealLogModel MapMealLog(SqlDataReader reader) => new()
    {
        MealLogId = reader.GetGuidValue("MealLogId"),
        UserId = reader.GetGuidValue("UserId"),
        LogDateUtc = DateOnly.FromDateTime(reader.GetDateTimeValue("LogDateUtc")),
        MealType = reader.GetStringValue("MealType"),
        Title = reader.GetStringValue("Title"),
        CaloriesKcal = reader.GetInt16Value("CaloriesKcal"),
        ProteinG = reader.GetInt16Value("ProteinG"),
        CarbsG = reader.GetInt16Value("CarbsG"),
        FatsG = reader.GetInt16Value("FatsG"),
        Status = reader.GetStringValue("Status"),
        PlannedLocalTime = reader.IsDBNull(reader.GetOrdinal("PlannedLocalTime")) ? null : reader.GetTimeSpanValue("PlannedLocalTime"),
        LoggedAtUtc = reader.GetNullableDateTime("LoggedAtUtc"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc")
    };

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
        SuggestedMonth = reader.IsDBNull(reader.GetOrdinal("SuggestedMonth")) ? null : reader.GetByteValue("SuggestedMonth"),
        IsSystemDefault = reader.GetBoolValue("IsSystemDefault"),
        SortOrder = reader.GetInt32Value("SortOrder")
    };
}
