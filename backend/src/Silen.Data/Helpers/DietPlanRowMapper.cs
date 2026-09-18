using Microsoft.Data.SqlClient;
using Silen.Common.Helpers;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>App-facing diet plan rows (MealPlanning.sql's usp_DietPlans_*, UserDietPlans.sql) -
/// the meal-planning equivalent of the split mappers in <see cref="WorkoutRowMapper"/>.</summary>
public static class DietPlanRowMapper
{
    public static DietPlanModel MapDietPlan(SqlDataReader reader) => new()
    {
        DietPlanId = reader.GetGuidValue("DietPlanId"),
        Name = reader.GetStringValue("Name"),
        Description = reader.GetNullableString("Description"),
        HeroImageUrl = reader.GetNullableString("HeroImageUrl"),
        PeriodType = reader.GetStringValue("PeriodType"),
        DurationDays = reader.GetByteValue("DurationDays"),
        IsSystemDefault = reader.GetBoolValue("IsSystemDefault"),
        SortOrder = reader.GetInt32Value("SortOrder"),
        Visibility = reader.GetNullableString("Visibility") ?? "Public",
        OwnerUserId = reader.GetNullableGuid("OwnerUserId"),
        IsAiGenerated = HasColumn(reader, "IsAiGenerated") && reader.GetBoolValue("IsAiGenerated"),
        AiKeptAtUtc = HasColumn(reader, "AiKeptAtUtc") ? reader.GetNullableDateTime("AiKeptAtUtc") : null
    };

    public static ActiveDietPlanModel MapActiveDietPlan(SqlDataReader reader) => new()
    {
        UserId = reader.GetGuidValue("UserId"),
        DietPlanId = reader.GetGuidValue("DietPlanId"),
        ActivatedAtUtc = reader.GetDateTimeValue("ActivatedAtUtc"),
        Name = reader.GetNullableString("Name"),
        DurationDays = reader.GetByteValue("DurationDays")
    };

    public static DietPlanDayModel MapDietPlanDay(SqlDataReader reader) => new()
    {
        DietPlanDayId = reader.GetGuidValue("DietPlanDayId"),
        DayIndex = reader.GetByteValue("DayIndex"),
        Title = reader.GetNullableString("Title")
    };

    public static DietPlanMealModel MapDietPlanMeal(SqlDataReader reader) => new()
    {
        DietPlanDayId = reader.GetGuidValue("DietPlanDayId"),
        DietPlanMealId = reader.GetGuidValue("DietPlanMealId"),
        MealType = reader.GetStringValue("MealType"),
        MealSuggestionId = reader.GetGuidValue("MealSuggestionId"),
        Title = reader.GetStringValue("Title"),
        Description = reader.GetNullableString("Description"),
        CaloriesKcal = reader.GetInt16Value("CaloriesKcal"),
        ProteinG = reader.GetInt16Value("ProteinG"),
        CarbsG = reader.GetInt16Value("CarbsG"),
        FatsG = reader.GetInt16Value("FatsG"),
        SortOrder = reader.GetInt32Value("SortOrder")
    };

    /// <summary>One dbo.MealSuggestionIngredients.IngredientText line from the
    /// shopping-list result set of usp_DietPlans_GetDetail.</summary>
    public static string MapIngredientText(SqlDataReader reader) => reader.GetStringValue("IngredientText");

    private static bool HasColumn(SqlDataReader reader, string column)
    {
        for (var i = 0; i < reader.FieldCount; i++)
        {
            if (string.Equals(reader.GetName(i), column, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }
}
