using Microsoft.Data.SqlClient;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

public static class SettingsRowMapper
{
    public static UserSettingsModel MapSettings(SqlDataReader reader) => new()
    {
        UserId = reader.GetGuidValue("UserId"),
        TargetWaterMl = reader.GetInt32Value("TargetWaterMl"),
        NotificationsEnabled = reader.GetBoolValue("NotificationsEnabled"),
        NotificationLocalTime = reader.GetTimeSpanValue("NotificationLocalTime"),
        TimeZoneId = reader.GetStringValue("TimeZoneId"),
        WeightUnit = reader.GetStringValue("WeightUnit"),
        DistanceUnit = reader.GetStringValue("DistanceUnit"),
        RestTimerSoundEnabled = reader.GetBoolValue("RestTimerSoundEnabled"),
        BarbellStandardKg = reader.GetDecimalValue("BarbellStandardKg"),
        AppearanceMode = reader.GetStringValue("AppearanceMode"),
        ReceiveWeeklyAiPlans = reader.GetBoolValue("ReceiveWeeklyAiPlans"),
        AutoActivateAiPlans = reader.GetBoolValue("AutoActivateAiPlans"),
        UpdatedAtUtc = reader.GetDateTimeValue("UpdatedAtUtc")
    };
}
