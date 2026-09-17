using Microsoft.Data.SqlClient;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>Outside helper mapping the weekly AI plan run/delivery/candidate rows.</summary>
public static class WeeklyAiPlanRowMapper
{
    public static WeeklyAiPlanRunModel MapRun(SqlDataReader reader) => new()
    {
        RunId = reader.GetGuidValue("RunId"),
        WeekStartUtc = reader.GetDateTimeValue("WeekStartUtc"),
        Status = reader.GetStringValue("Status"),
        UsersConsidered = reader.GetInt32Value("UsersConsidered"),
        PlansGenerated = reader.GetInt32Value("PlansGenerated"),
        NotificationsSent = reader.GetInt32Value("NotificationsSent"),
        Failures = reader.GetInt32Value("Failures"),
        StartedAtUtc = reader.GetDateTimeValue("StartedAtUtc"),
        CompletedAtUtc = reader.GetNullableDateTime("CompletedAtUtc")
    };

    public static PlanSubscriberModel MapCandidateUser(SqlDataReader reader) => new()
    {
        UserId = reader.GetGuidValue("UserId"),
        DisplayName = reader.GetNullableString("DisplayName"),
        Email = reader.GetNullableString("Email"),
        PlanCode = reader.GetStringValue("PlanCode"),
        ExpiresAtUtc = reader.GetNullableDateTime("ExpiresAtUtc")
    };
}
