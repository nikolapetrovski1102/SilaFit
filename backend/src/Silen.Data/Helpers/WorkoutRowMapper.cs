using Npgsql;
using Silen.Common.Helpers;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>Outside helper mapping Bodyweight/Streak/WorkoutSession/Splits/Exercises/Plans rows.</summary>
public static class WorkoutRowMapper
{
    /// <summary>WeightKg is AES-256-GCM ciphertext (see BodyweightProvider) - decrypted here with <paramref name="key"/>.</summary>
    public static BodyweightEntryModel MapBodyweightEntry(NpgsqlDataReader reader, byte[] key) => new()
    {
        BodyweightLogId = reader.GetGuidValue("BodyweightLogId"),
        WeightKg = FieldCipher.DecryptDecimal(reader.GetBytesValue("WeightKg"), key),
        LoggedAtUtc = reader.GetDateTimeValue("LoggedAtUtc")
    };

    public static StreakStatusModel MapStreakStatus(NpgsqlDataReader reader) => new()
    {
        CurrentStreakDays = reader.GetInt32Value("CurrentStreakDays"),
        WeeklyCompliancePercent = reader.GetInt32Value("WeeklyCompliancePercent")
    };

    public static WeekDayStatusModel MapWeekDayStatus(NpgsqlDataReader reader) => new()
    {
        SessionDate = reader.GetDateTimeValue("SessionDate"),
        SessionStatus = reader.GetNullableString("SessionStatus")
    };

    public static TodaySessionModel MapTodaySession(NpgsqlDataReader reader) => new()
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

    public static TargetExerciseModel MapTargetExercise(NpgsqlDataReader reader) => new()
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

    public static WorkoutSessionCompletionModel MapCompletion(NpgsqlDataReader reader) => new()
    {
        WorkoutSessionId = reader.GetGuidValue("WorkoutSessionId"),
        Status = reader.GetStringValue("Status"),
        CompletedAtUtc = reader.GetNullableDateTime("CompletedAtUtc"),
        DurationMinutes = reader.GetNullableInt16("DurationMinutes"),
        CaloriesEstimate = reader.GetNullableInt16("CaloriesEstimate"),
        RpeScore = reader.GetNullableDecimal("RpeScore"),
        TonnageKg = reader.GetNullableDecimal("TonnageKg")
    };

    public static RangeSummaryModel MapRangeSummary(NpgsqlDataReader reader) => new()
    {
        CompletedSessions = reader.GetInt32Value("CompletedSessions"),
        ScheduledSessions = reader.GetInt32Value("ScheduledSessions"),
        TotalTonnageKg = reader.GetDecimalValue("TotalTonnageKg"),
        AvgRpe = reader.GetDecimalValue("AvgRpe")
    };

    public static DaySessionStatusModel MapDaySessionStatus(NpgsqlDataReader reader) => new()
    {
        ScheduledDateUtc = reader.GetDateTimeValue("ScheduledDateUtc"),
        Status = reader.GetStringValue("Status"),
        TonnageKg = HasColumn(reader, "TonnageKg") ? reader.GetNullableDecimal("TonnageKg") : null,
        RpeScore = HasColumn(reader, "RpeScore") ? reader.GetNullableDecimal("RpeScore") : null
    };

    public static SetLogModel MapSetLog(NpgsqlDataReader reader) => new()
    {
        ExerciseId = reader.GetGuidValue("ExerciseId"),
        ExerciseName = reader.GetStringValue("ExerciseName"),
        SetNumber = reader.GetByteValue("SetNumber"),
        WeightKg = reader.GetDecimalValue("WeightKg"),
        Reps = reader.GetInt16Value("Reps"),
        CompletedAtUtc = reader.GetDateTimeValue("CompletedAtUtc")
    };

    public static PersonalRecordModel MapPersonalRecord(NpgsqlDataReader reader) => new()
    {
        ExerciseId = reader.GetGuidValue("ExerciseId"),
        ExerciseName = reader.GetStringValue("ExerciseName"),
        WeightKg = reader.GetDecimalValue("WeightKg"),
        Reps = reader.GetInt16Value("Reps"),
        AchievedAtUtc = reader.GetDateTimeValue("CompletedAtUtc"),
        PreviousBestWeightKg = reader.GetNullableDecimal("PreviousBestWeightKg"),
        IsPerDumbbell = reader.GetBoolValue("IsPerDumbbell")
    };

    public static TrackedExerciseModel MapTrackedExercise(NpgsqlDataReader reader) => new()
    {
        ExerciseId = reader.GetGuidValue("ExerciseId"),
        ExerciseName = reader.GetStringValue("ExerciseName"),
        SessionCount = reader.GetInt32Value("SessionCount"),
        LastTrainedAtUtc = reader.GetDateTimeValue("LastTrainedAtUtc"),
        IsPerDumbbell = reader.GetBoolValue("IsPerDumbbell")
    };

    public static ExerciseProgressPointModel MapExerciseProgressPoint(NpgsqlDataReader reader) => new()
    {
        ScheduledDateUtc = reader.GetDateTimeValue("ScheduledDateUtc"),
        TopWeightKg = reader.GetDecimalValue("TopWeightKg"),
        TopSetReps = reader.GetInt16Value("TopSetReps"),
        EstimatedOneRmKg = reader.GetDecimalValue("EstimatedOneRmKg"),
        TotalVolumeKg = reader.GetDecimalValue("TotalVolumeKg"),
        TotalReps = reader.GetInt32Value("TotalReps"),
        SetCount = reader.GetInt32Value("SetCount")
    };

    public static WorkoutSplitModel MapSplit(NpgsqlDataReader reader) => new()
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
        RecommendedGoal = HasColumn(reader, "RecommendedGoal") ? reader.GetNullableString("RecommendedGoal") : null,
        Visibility = HasColumn(reader, "Visibility") ? reader.GetNullableString("Visibility") ?? "Public" : "Public",
        AvgSessionMinutes = HasColumn(reader, "AvgSessionMinutes") ? reader.GetInt32Value("AvgSessionMinutes") : 0,
        DaysPerWeek = HasColumn(reader, "DaysPerWeek") ? reader.GetNullableByte("DaysPerWeek") : null,
        ProgramDurationWeeks = HasColumn(reader, "ProgramDurationWeeks") ? reader.GetNullableInt16("ProgramDurationWeeks") : null,
        MinSessionMinutes = HasColumn(reader, "MinSessionMinutes") ? reader.GetNullableInt16("MinSessionMinutes") : null,
        MaxSessionMinutes = HasColumn(reader, "MaxSessionMinutes") ? reader.GetNullableInt16("MaxSessionMinutes") : null,
        EquipmentRequired = HasColumn(reader, "EquipmentRequired") ? reader.GetNullableString("EquipmentRequired") : null,
        TargetGender = HasColumn(reader, "TargetGender") ? reader.GetNullableString("TargetGender") : null,
        WorkoutTypeLabel = HasColumn(reader, "WorkoutTypeLabel") ? reader.GetNullableString("WorkoutTypeLabel") : null,
        SourceCategoriesJson = HasColumn(reader, "SourceCategoriesJson") ? reader.GetNullableString("SourceCategoriesJson") : null,
        OwnerUserId = HasColumn(reader, "OwnerUserId") ? reader.GetNullableGuid("OwnerUserId") : null,
        IsAiGenerated = HasColumn(reader, "IsAiGenerated") && reader.GetBoolValue("IsAiGenerated"),
        AiKeptAtUtc = HasColumn(reader, "AiKeptAtUtc") ? reader.GetNullableDateTime("AiKeptAtUtc") : null
    };

    public static SplitDayModel MapSplitDay(NpgsqlDataReader reader) => new()
    {
        SplitDayId = reader.GetGuidValue("SplitDayId"),
        DayIndex = reader.GetByteValue("DayIndex"),
        Title = reader.GetStringValue("Title"),
        FocusLabel = reader.GetNullableString("FocusLabel"),
        EstimatedMinutes = reader.GetInt16Value("EstimatedMinutes"),
        IsRestDay = reader.GetBoolValue("IsRestDay")
    };

    public static SplitDayExerciseModel MapSplitDayExercise(NpgsqlDataReader reader) => new()
    {
        SplitDayId = reader.GetGuidValue("SplitDayId"),
        SplitDayExerciseId = reader.GetGuidValue("SplitDayExerciseId"),
        ExerciseId = reader.GetGuidValue("ExerciseId"),
        Name = reader.GetStringValue("Name"),
        MuscleGroup = reader.GetStringValue("MuscleGroup"),
        SortOrder = reader.GetByteValue("SortOrder"),
        TargetSets = reader.GetByteValue("TargetSets"),
        TargetRepsLow = reader.GetByteValue("TargetRepsLow"),
        TargetRepsHigh = reader.GetByteValue("TargetRepsHigh")
    };

    public static ActiveSplitModel MapActiveSplit(NpgsqlDataReader reader) => new()
    {
        UserId = reader.GetGuidValue("UserId"),
        SplitId = reader.GetGuidValue("SplitId"),
        ActivatedAtUtc = reader.GetDateTimeValue("ActivatedAtUtc"),
        Name = HasColumn(reader, "Name") ? reader.GetNullableString("Name") : null,
        DurationDays = HasColumn(reader, "DurationDays") ? reader.GetByteValue("DurationDays") : null,
        IsAutoAssigned = HasColumn(reader, "IsAutoAssigned") && reader.GetBoolValue("IsAutoAssigned")
    };

    public static ExerciseModel MapExercise(NpgsqlDataReader reader) => new()
    {
        ExerciseId = reader.GetGuidValue("ExerciseId"),
        Name = reader.GetStringValue("Name"),
        MuscleGroup = reader.GetStringValue("MuscleGroup"),
        EquipmentType = reader.GetNullableString("EquipmentType"),
        IsCompound = reader.GetBoolValue("IsCompound"),
        DemoVideoUrl = reader.GetNullableString("DemoVideoUrl"),
        IsCustom = reader.GetBoolValue("IsCustom")
    };

    public static SubscriptionPlanModel MapPlan(NpgsqlDataReader reader) => new()
    {
        PlanId = reader.GetGuidValue("PlanId"),
        Code = reader.GetStringValue("Code"),
        Name = reader.GetStringValue("Name"),
        Tagline = reader.GetNullableString("Tagline"),
        MonthlyPrice = reader.GetDecimalValue("MonthlyPrice"),
        YearlyPrice = reader.GetDecimalValue("YearlyPrice"),
        IsFeatured = reader.GetBoolValue("IsFeatured"),
        SortOrder = reader.GetInt32Value("SortOrder"),
        AppStoreMonthlyProductId = HasColumn(reader, "AppStoreMonthlyProductId") ? reader.GetNullableString("AppStoreMonthlyProductId") : null,
        AppStoreYearlyProductId = HasColumn(reader, "AppStoreYearlyProductId") ? reader.GetNullableString("AppStoreYearlyProductId") : null,
        PlayStoreMonthlyProductId = HasColumn(reader, "PlayStoreMonthlyProductId") ? reader.GetNullableString("PlayStoreMonthlyProductId") : null,
        PlayStoreYearlyProductId = HasColumn(reader, "PlayStoreYearlyProductId") ? reader.GetNullableString("PlayStoreYearlyProductId") : null
    };

    public static PlanFeatureModel MapPlanFeature(NpgsqlDataReader reader) => new()
    {
        PlanId = reader.GetGuidValue("PlanId"),
        FeatureText = reader.GetStringValue("FeatureText"),
        SortOrder = reader.GetByteValue("SortOrder"),
        IsHighlighted = reader.GetBoolValue("IsHighlighted")
    };

    public static PlanSubscriberModel MapPlanSubscriber(NpgsqlDataReader reader) => new()
    {
        UserId = reader.GetGuidValue("UserId"),
        DisplayName = reader.GetNullableString("DisplayName"),
        Email = reader.GetNullableString("Email"),
        PlanCode = reader.GetStringValue("PlanCode"),
        ExpiresAtUtc = reader.GetNullableDateTime("ExpiresAtUtc")
    };

    public static UserSubscriptionModel MapSubscription(NpgsqlDataReader reader) => new()
    {
        UserId = reader.GetGuidValue("UserId"),
        PlanId = reader.GetGuidValue("PlanId"),
        BillingCycle = reader.GetStringValue("BillingCycle"),
        Status = reader.GetStringValue("Status"),
        StartedAtUtc = reader.GetDateTimeValue("StartedAtUtc"),
        ExpiresAtUtc = reader.GetNullableDateTime("ExpiresAtUtc"),
        PlanCode = HasColumn(reader, "Code") ? reader.GetNullableString("Code") : null,
        PlanName = HasColumn(reader, "Name") ? reader.GetNullableString("Name") : null,
        LatestReceiptId = HasColumn(reader, "LatestReceiptId") ? reader.GetNullableGuid("LatestReceiptId") : null,
        AutoRenewing = HasColumn(reader, "AutoRenewing") && reader.GetBoolValue("AutoRenewing"),
        IsPartnerGrant = HasColumn(reader, "IsPartnerGrant") && reader.GetBoolValue("IsPartnerGrant")
    };

    public static SubscriptionReceiptModel MapReceipt(NpgsqlDataReader reader) => new()
    {
        ReceiptId = reader.GetGuidValue("ReceiptId"),
        UserId = reader.GetGuidValue("UserId"),
        PlanId = reader.GetGuidValue("PlanId"),
        Store = reader.GetStringValue("Store"),
        ProductId = reader.GetStringValue("ProductId"),
        TransactionId = reader.GetStringValue("TransactionId"),
        OriginalTransactionId = reader.GetNullableString("OriginalTransactionId"),
        PurchaseToken = HasColumn(reader, "PurchaseToken") ? reader.GetNullableString("PurchaseToken") : null,
        RawPayload = HasColumn(reader, "RawPayload") ? reader.GetNullableString("RawPayload") : null,
        Status = reader.GetStringValue("Status"),
        ExpiresAtUtc = reader.GetNullableDateTime("ExpiresAtUtc"),
        AutoRenewing = reader.GetBoolValue("AutoRenewing"),
        VerifiedAtUtc = HasColumn(reader, "VerifiedAtUtc") ? reader.GetDateTimeValue("VerifiedAtUtc") : default,
        CreatedAtUtc = HasColumn(reader, "CreatedAtUtc") ? reader.GetDateTimeValue("CreatedAtUtc") : default
    };

    public static PromoCodeRedemptionModel MapPromoCodeRedemption(NpgsqlDataReader reader) => new()
    {
        Status = reader.GetStringValue("Status"),
        Code = reader.GetNullableString("Code"),
        PlayOfferId = reader.GetNullableString("PlayOfferId"),
        ExpiresAtUtc = reader.GetNullableDateTime("ExpiresAtUtc")
    };

    public static PlanEntitlementsModel MapPlanEntitlements(NpgsqlDataReader reader) => new()
    {
        MaxActiveSplits = reader.GetNullableInt32("MaxActiveSplits"),
        MaxActiveDietPlans = reader.GetNullableInt32("MaxActiveDietPlans"),
        AllowAiGeneration = reader.GetBoolValue("AllowAiGeneration")
    };

    private static bool HasColumn(NpgsqlDataReader reader, string column)
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
