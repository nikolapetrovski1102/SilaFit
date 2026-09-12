using Microsoft.Data.SqlClient;
using Silen.Common.Helpers;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>Outside helper mapping Bodyweight/Streak/WorkoutSession/Splits/Exercises/Plans rows.</summary>
public static class WorkoutRowMapper
{
    /// <summary>WeightKg is AES-256-GCM ciphertext (see BodyweightProvider) - decrypted here with <paramref name="key"/>.</summary>
    public static BodyweightEntryModel MapBodyweightEntry(SqlDataReader reader, byte[] key) => new()
    {
        BodyweightLogId = reader.GetGuidValue("BodyweightLogId"),
        WeightKg = FieldCipher.DecryptDecimal(reader.GetBytesValue("WeightKg"), key),
        LoggedAtUtc = reader.GetDateTimeValue("LoggedAtUtc")
    };

    public static StreakStatusModel MapStreakStatus(SqlDataReader reader) => new()
    {
        CurrentStreakDays = reader.GetInt32Value("CurrentStreakDays"),
        WeeklyCompliancePercent = reader.GetInt32Value("WeeklyCompliancePercent")
    };

    public static WeekDayStatusModel MapWeekDayStatus(SqlDataReader reader) => new()
    {
        SessionDate = reader.GetDateTimeValue("SessionDate"),
        SessionStatus = reader.GetNullableString("SessionStatus")
    };

    public static TodaySessionModel MapTodaySession(SqlDataReader reader) => new()
    {
        WorkoutSessionId = reader.GetGuidValue("WorkoutSessionId"),
        Status = reader.GetStringValue("Status"),
        ScheduledDateUtc = reader.GetDateTimeValue("ScheduledDateUtc"),
        SplitDayId = reader.GetNullableGuid("SplitDayId"),
        Title = reader.GetNullableString("Title"),
        FocusLabel = reader.GetNullableString("FocusLabel"),
        EstimatedMinutes = reader.GetNullableInt16("EstimatedMinutes"),
        IsRestDay = reader.GetNullableBool("IsRestDay")
    };

    public static TargetExerciseModel MapTargetExercise(SqlDataReader reader) => new()
    {
        ExerciseId = reader.GetGuidValue("ExerciseId"),
        Name = reader.GetStringValue("Name"),
        MuscleGroup = reader.GetStringValue("MuscleGroup"),
        EquipmentType = HasColumn(reader, "EquipmentType") ? reader.GetNullableString("EquipmentType") : null,
        DemoVideoUrl = HasColumn(reader, "DemoVideoUrl") ? reader.GetNullableString("DemoVideoUrl") : null,
        SortOrder = reader.GetByteValue("SortOrder"),
        TargetSets = reader.GetByteValue("TargetSets"),
        TargetRepsLow = reader.GetByteValue("TargetRepsLow"),
        TargetRepsHigh = reader.GetByteValue("TargetRepsHigh")
    };

    public static WorkoutSessionCompletionModel MapCompletion(SqlDataReader reader) => new()
    {
        WorkoutSessionId = reader.GetGuidValue("WorkoutSessionId"),
        Status = reader.GetStringValue("Status"),
        CompletedAtUtc = reader.GetNullableDateTime("CompletedAtUtc"),
        DurationMinutes = reader.GetNullableInt16("DurationMinutes"),
        CaloriesEstimate = reader.GetNullableInt16("CaloriesEstimate"),
        RpeScore = reader.GetNullableDecimal("RpeScore"),
        TonnageKg = reader.GetNullableDecimal("TonnageKg")
    };

    public static RangeSummaryModel MapRangeSummary(SqlDataReader reader) => new()
    {
        CompletedSessions = reader.GetInt32Value("CompletedSessions"),
        ScheduledSessions = reader.GetInt32Value("ScheduledSessions"),
        TotalTonnageKg = reader.GetDecimalValue("TotalTonnageKg"),
        AvgRpe = reader.GetDecimalValue("AvgRpe")
    };

    public static DaySessionStatusModel MapDaySessionStatus(SqlDataReader reader) => new()
    {
        ScheduledDateUtc = reader.GetDateTimeValue("ScheduledDateUtc"),
        Status = reader.GetStringValue("Status"),
        TonnageKg = HasColumn(reader, "TonnageKg") ? reader.GetNullableDecimal("TonnageKg") : null,
        RpeScore = HasColumn(reader, "RpeScore") ? reader.GetNullableDecimal("RpeScore") : null
    };

    public static WorkoutSplitModel MapSplit(SqlDataReader reader) => new()
    {
        SplitId = reader.GetGuidValue("SplitId"),
        Name = reader.GetStringValue("Name"),
        Category = reader.GetStringValue("Category"),
        Level = reader.GetStringValue("Level"),
        DurationDays = reader.GetByteValue("DurationDays"),
        Description = reader.GetNullableString("Description"),
        HeroImageUrl = reader.GetNullableString("HeroImageUrl"),
        IsSystemDefault = reader.GetBoolValue("IsSystemDefault"),
        SortOrder = HasColumn(reader, "SortOrder") ? reader.GetInt32Value("SortOrder") : 0,
        RecommendedGoal = HasColumn(reader, "RecommendedGoal") ? reader.GetNullableString("RecommendedGoal") : null
    };

    public static SplitDayModel MapSplitDay(SqlDataReader reader) => new()
    {
        SplitDayId = reader.GetGuidValue("SplitDayId"),
        DayIndex = reader.GetByteValue("DayIndex"),
        Title = reader.GetStringValue("Title"),
        FocusLabel = reader.GetNullableString("FocusLabel"),
        EstimatedMinutes = reader.GetInt16Value("EstimatedMinutes"),
        IsRestDay = reader.GetBoolValue("IsRestDay")
    };

    public static SplitDayExerciseModel MapSplitDayExercise(SqlDataReader reader) => new()
    {
        SplitDayId = reader.GetGuidValue("SplitDayId"),
        ExerciseId = reader.GetGuidValue("ExerciseId"),
        Name = reader.GetStringValue("Name"),
        SortOrder = reader.GetByteValue("SortOrder"),
        TargetSets = reader.GetByteValue("TargetSets"),
        TargetRepsLow = reader.GetByteValue("TargetRepsLow"),
        TargetRepsHigh = reader.GetByteValue("TargetRepsHigh")
    };

    public static ActiveSplitModel MapActiveSplit(SqlDataReader reader) => new()
    {
        UserId = reader.GetGuidValue("UserId"),
        SplitId = reader.GetGuidValue("SplitId"),
        ActivatedAtUtc = reader.GetDateTimeValue("ActivatedAtUtc"),
        Name = HasColumn(reader, "Name") ? reader.GetNullableString("Name") : null,
        DurationDays = HasColumn(reader, "DurationDays") ? reader.GetByteValue("DurationDays") : null
    };

    public static ExerciseModel MapExercise(SqlDataReader reader) => new()
    {
        ExerciseId = reader.GetGuidValue("ExerciseId"),
        Name = reader.GetStringValue("Name"),
        MuscleGroup = reader.GetStringValue("MuscleGroup"),
        EquipmentType = reader.GetNullableString("EquipmentType"),
        IsCompound = reader.GetBoolValue("IsCompound"),
        DemoVideoUrl = reader.GetNullableString("DemoVideoUrl")
    };

    public static SubscriptionPlanModel MapPlan(SqlDataReader reader) => new()
    {
        PlanId = reader.GetGuidValue("PlanId"),
        Code = reader.GetStringValue("Code"),
        Name = reader.GetStringValue("Name"),
        Tagline = reader.GetNullableString("Tagline"),
        MonthlyPrice = reader.GetDecimalValue("MonthlyPrice"),
        YearlyPrice = reader.GetDecimalValue("YearlyPrice"),
        IsFeatured = reader.GetBoolValue("IsFeatured"),
        SortOrder = reader.GetInt32Value("SortOrder")
    };

    public static PlanFeatureModel MapPlanFeature(SqlDataReader reader) => new()
    {
        PlanId = reader.GetGuidValue("PlanId"),
        FeatureText = reader.GetStringValue("FeatureText"),
        SortOrder = reader.GetByteValue("SortOrder"),
        IsHighlighted = reader.GetBoolValue("IsHighlighted")
    };

    public static UserSubscriptionModel MapSubscription(SqlDataReader reader) => new()
    {
        UserId = reader.GetGuidValue("UserId"),
        PlanId = reader.GetGuidValue("PlanId"),
        BillingCycle = reader.GetStringValue("BillingCycle"),
        Status = reader.GetStringValue("Status"),
        StartedAtUtc = reader.GetDateTimeValue("StartedAtUtc"),
        ExpiresAtUtc = reader.GetNullableDateTime("ExpiresAtUtc"),
        PlanCode = HasColumn(reader, "Code") ? reader.GetNullableString("Code") : null,
        PlanName = HasColumn(reader, "Name") ? reader.GetNullableString("Name") : null
    };

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
