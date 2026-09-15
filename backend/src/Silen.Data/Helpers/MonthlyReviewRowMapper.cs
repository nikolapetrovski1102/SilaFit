using Microsoft.Data.SqlClient;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>Outside helper mapping the monthly review run/delivery rows.</summary>
public static class MonthlyReviewRowMapper
{
    public static MonthlyReviewRunModel MapRun(SqlDataReader reader) => new()
    {
        RunId = reader.GetGuidValue("RunId"),
        PeriodYear = reader.GetInt16Value("PeriodYear"),
        PeriodMonth = reader.GetByteValue("PeriodMonth"),
        PlanCode = reader.GetStringValue("PlanCode"),
        Status = reader.GetStringValue("Status"),
        UsersConsidered = reader.GetInt32Value("UsersConsidered"),
        ReportsGenerated = reader.GetInt32Value("ReportsGenerated"),
        EmailsSent = reader.GetInt32Value("EmailsSent"),
        Failures = reader.GetInt32Value("Failures"),
        StartedAtUtc = reader.GetDateTimeValue("StartedAtUtc"),
        CompletedAtUtc = reader.GetNullableDateTime("CompletedAtUtc")
    };
}
