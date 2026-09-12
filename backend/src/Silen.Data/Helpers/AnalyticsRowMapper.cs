using Microsoft.Data.SqlClient;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>Row mapper for the monthly AI analytics feature - kept separate from WorkoutRowMapper
/// since it's a distinct domain (AI prompt templates + generated reports).</summary>
public static class AnalyticsRowMapper
{
    public static MonthlySnapshotModel MapMonthlySnapshot(SqlDataReader reader) => new()
    {
        DisplayName = reader.GetStringValue("DisplayName"),
        CompletedSessions = reader.GetInt32Value("CompletedSessions"),
        ScheduledSessions = reader.GetInt32Value("ScheduledSessions"),
        TotalTonnageKg = reader.GetDecimalValue("TotalTonnageKg"),
        AvgRpe = reader.GetDecimalValue("AvgRpe"),
        CurrentStreakDays = reader.GetInt32Value("CurrentStreakDays"),
        WeeklyCompliancePercent = reader.GetInt32Value("WeeklyCompliancePercent"),
        StartWeightKg = reader.GetNullableDecimal("StartWeightKg"),
        EndWeightKg = reader.GetNullableDecimal("EndWeightKg"),
        LoggedMealDays = reader.GetInt32Value("LoggedMealDays"),
        TotalDaysInRange = reader.GetInt32Value("TotalDaysInRange"),
        AvgCaloriesLogged = reader.GetNullableDecimal("AvgCaloriesLogged"),
        TargetCalories = reader.GetNullableInt16("TargetCalories")
    };

    public static AiPromptTemplateModel MapPromptTemplate(SqlDataReader reader) => new()
    {
        PromptTemplateId = reader.GetGuidValue("PromptTemplateId"),
        TemplateKey = reader.GetStringValue("TemplateKey"),
        SystemPrompt = reader.GetStringValue("SystemPrompt"),
        UserPromptTemplate = reader.GetStringValue("UserPromptTemplate"),
        Model = reader.GetStringValue("Model"),
        IsActive = reader.GetBoolValue("IsActive"),
        UpdatedAtUtc = reader.GetDateTimeValue("UpdatedAtUtc")
    };

    public static MonthlyAnalyticsReportModel MapReport(SqlDataReader reader) => new()
    {
        ReportId = reader.GetGuidValue("ReportId"),
        UserId = reader.GetGuidValue("UserId"),
        ReportYear = reader.GetInt16Value("ReportYear"),
        ReportMonth = reader.GetByteValue("ReportMonth"),
        SnapshotJson = reader.GetStringValue("SnapshotJson"),
        ResultJson = reader.GetStringValue("ResultJson"),
        GeneratedAtUtc = reader.GetDateTimeValue("GeneratedAtUtc")
    };
}
