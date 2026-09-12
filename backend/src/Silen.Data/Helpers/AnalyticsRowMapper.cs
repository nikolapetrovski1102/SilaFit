using Microsoft.Data.SqlClient;
using Silen.Common.Helpers;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>Row mapper for the monthly AI analytics feature - kept separate from WorkoutRowMapper
/// since it's a distinct domain (AI prompt templates + generated reports).</summary>
public static class AnalyticsRowMapper
{
    /// <summary>StartWeightKg/EndWeightKg/AvgCaloriesLogged are left at their default (null) here -
    /// usp_Analytics_GetMonthlySnapshot no longer computes them (BodyweightLogs.WeightKg and
    /// MealLogs.CaloriesKcal are AES-256-GCM ciphertext); AnalyticsProvider fills them in
    /// afterwards from IBodyweightProvider/IMealPlanningProvider. TargetCalories IS returned by
    /// that proc, as ciphertext, so it's decrypted here with <paramref name="key"/>.</summary>
    public static MonthlySnapshotModel MapMonthlySnapshot(SqlDataReader reader, byte[] key)
    {
        var targetCalories = reader.GetNullableBytes("TargetCalories");
        return new MonthlySnapshotModel
        {
            DisplayName = reader.GetStringValue("DisplayName"),
            CompletedSessions = reader.GetInt32Value("CompletedSessions"),
            ScheduledSessions = reader.GetInt32Value("ScheduledSessions"),
            TotalTonnageKg = reader.GetDecimalValue("TotalTonnageKg"),
            AvgRpe = reader.GetDecimalValue("AvgRpe"),
            CurrentStreakDays = reader.GetInt32Value("CurrentStreakDays"),
            WeeklyCompliancePercent = reader.GetInt32Value("WeeklyCompliancePercent"),
            LoggedMealDays = reader.GetInt32Value("LoggedMealDays"),
            TotalDaysInRange = reader.GetInt32Value("TotalDaysInRange"),
            TargetCalories = targetCalories is null ? null : (short)FieldCipher.DecryptInt(targetCalories, key)
        };
    }

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
