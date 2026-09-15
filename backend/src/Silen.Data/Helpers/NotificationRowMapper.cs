using Microsoft.Data.SqlClient;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

public static class NotificationRowMapper
{
    public static UserDeviceTokenModel MapDeviceToken(SqlDataReader reader) => new()
    {
        DeviceTokenId = reader.GetGuidValue("DeviceTokenId"),
        UserId = reader.GetGuidValue("UserId"),
        Platform = reader.GetStringValue("Platform"),
        PushToken = reader.GetStringValue("PushToken"),
        TimeZoneId = reader.GetNullableString("TimeZoneId"),
        IsActive = reader.GetBoolValue("IsActive"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc"),
        UpdatedAtUtc = reader.GetDateTimeValue("UpdatedAtUtc"),
        LastSeenAtUtc = reader.GetDateTimeValue("LastSeenAtUtc")
    };

    public static NotificationCandidateModel MapCandidate(SqlDataReader reader) => new()
    {
        UserId = reader.GetGuidValue("UserId"),
        DisplayName = reader.GetNullableString("DisplayName"),
        NotificationsEnabled = reader.GetBoolValue("NotificationsEnabled"),
        NotificationLocalTime = reader.GetTimeSpanValue("NotificationLocalTime"),
        TimeZoneId = reader.GetStringValue("TimeZoneId"),
        LastInteractionAtUtc = reader.GetNullableDateTime("LastInteractionAtUtc"),
        LastPushedAtUtc = reader.GetNullableDateTime("LastPushedAtUtc"),
        LastMotivationAtUtc = reader.GetNullableDateTime("LastMotivationAtUtc"),
        LastComebackAtUtc = reader.GetNullableDateTime("LastComebackAtUtc"),
        SentLast24h = reader.GetInt32Value("SentLast24h"),
        LastWorkoutStartedAtUtc = reader.GetNullableDateTime("LastWorkoutStartedAtUtc"),
        LastWorkoutCompletedAtUtc = reader.GetNullableDateTime("LastWorkoutCompletedAtUtc"),
        WorkoutsLast7Days = reader.GetInt32Value("WorkoutsLast7Days"),
        ActiveSessionStartedAtUtc = reader.GetNullableDateTime("ActiveSessionStartedAtUtc"),
        ActiveSessionLastActivityAtUtc = reader.GetNullableDateTime("ActiveSessionLastActivityAtUtc"),
        LastMealLoggedAtUtc = reader.GetNullableDateTime("LastMealLoggedAtUtc"),
        MealsLast24h = reader.GetInt32Value("MealsLast24h"),
        HasPaidSubscription = reader.GetBoolValue("HasPaidSubscription"),
        ActiveTokenCount = reader.GetInt32Value("ActiveTokenCount")
    };

    public static UserNotificationModel MapNotification(SqlDataReader reader) => new()
    {
        NotificationId = reader.GetGuidValue("NotificationId"),
        UserId = reader.GetGuidValue("UserId"),
        Category = reader.GetStringValue("Category"),
        Title = reader.GetStringValue("Title"),
        Body = reader.GetStringValue("Body"),
        DeepLink = reader.GetNullableString("DeepLink"),
        DedupeKey = reader.GetStringValue("DedupeKey"),
        Status = reader.GetStringValue("Status"),
        ProviderMessageId = reader.GetNullableString("ProviderMessageId"),
        ErrorMessage = reader.GetNullableString("ErrorMessage"),
        ScheduledLocalAt = reader.GetNullableDateTime("ScheduledLocalAt"),
        SentAtUtc = reader.GetNullableDateTime("SentAtUtc"),
        OpenedAtUtc = reader.GetNullableDateTime("OpenedAtUtc"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc")
    };
}
