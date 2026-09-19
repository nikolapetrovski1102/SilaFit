using Microsoft.Data.SqlClient;
using Silen.Common.Helpers;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>
/// Row mappers for the console's RBAC and content procedures (AdminRbac.sql,
/// AdminContent.sql, AdminSplits.sql). Outside helper like every other mapper, so
/// no Provider needs a private method to project a row.
/// </summary>
public static class AdminContentRowMapper
{
    /// <summary>
    /// Every admin mutation procedure returns the same three columns, so they all
    /// map through here and the service layer sees one shape.
    /// </summary>
    public static AdminMutationResultModel MapMutation(SqlDataReader reader) => new()
    {
        Outcome = reader.GetInt32Value("Outcome"),
        EntityId = reader.GetNullableGuid("EntityId"),
        Detail = reader.GetNullableString("Detail")
    };

    public static AdminRoleModel MapRole(SqlDataReader reader) => new()
    {
        RoleId = reader.GetGuidValue("RoleId"),
        Name = reader.GetStringValue("Name"),
        Description = reader.GetNullableString("Description"),
        IsSystemRole = reader.GetBoolValue("IsSystemRole"),
        PermissionCount = reader.GetInt32Value("PermissionCount"),
        OperatorCount = reader.GetInt32Value("OperatorCount")
    };

    public static AdminOperatorModel MapOperator(SqlDataReader reader) => new()
    {
        AdminUserId = reader.GetGuidValue("AdminUserId"),
        Username = reader.GetStringValue("Username"),
        RoleId = reader.GetNullableGuid("RoleId"),
        RoleName = reader.GetNullableString("RoleName"),
        IsActive = reader.GetBoolValue("IsActive"),
        LastLoginAtUtc = reader.GetNullableDateTime("LastLoginAtUtc"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc"),
        ActiveSessionCount = reader.GetInt32Value("ActiveSessionCount"),
        Email = reader.GetNullableString("Email"),
        EmailConfirmedAtUtc = reader.GetNullableDateTime("EmailConfirmedAtUtc")
    };

    public static AdminAuditEntryModel MapAuditEntry(SqlDataReader reader) => new()
    {
        AuditId = reader.GetGuidValue("AuditId"),
        AdminUserId = reader.GetNullableGuid("AdminUserId"),
        Username = reader.GetStringValue("Username"),
        Action = reader.GetStringValue("Action"),
        EntityType = reader.GetStringValue("EntityType"),
        EntityId = reader.GetNullableString("EntityId"),
        Summary = reader.GetNullableString("Summary"),
        CreatedFromIp = reader.GetNullableString("CreatedFromIp"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc")
    };

    public static AdminExerciseModel MapExercise(SqlDataReader reader) => new()
    {
        ExerciseId = reader.GetGuidValue("ExerciseId"),
        Name = reader.GetStringValue("Name"),
        MuscleGroup = reader.GetStringValue("MuscleGroup"),
        EquipmentType = reader.GetNullableString("EquipmentType"),
        IsCompound = reader.GetBoolValue("IsCompound"),
        DemoVideoUrl = reader.GetNullableString("DemoVideoUrl"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc"),
        UsageCount = reader.GetInt32Value("UsageCount")
    };

    public static AdminMealSuggestionModel MapMealSuggestion(SqlDataReader reader) => new()
    {
        MealSuggestionId = reader.GetGuidValue("MealSuggestionId"),
        Title = reader.GetStringValue("Title"),
        MealType = reader.GetStringValue("MealType"),
        Description = reader.GetNullableString("Description"),
        CaloriesKcal = reader.GetInt16Value("CaloriesKcal"),
        ProteinG = reader.GetInt16Value("ProteinG"),
        CarbsG = reader.GetInt16Value("CarbsG"),
        FatsG = reader.GetInt16Value("FatsG"),
        SuggestedMonth = reader.GetNullableByte("SuggestedMonth") is { } month ? month : null,
        IsSystemDefault = reader.GetBoolValue("IsSystemDefault"),
        SortOrder = reader.GetInt32Value("SortOrder"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc")
    };

    public static AdminPlanModel MapPlan(SqlDataReader reader) => new()
    {
        PlanId = reader.GetGuidValue("PlanId"),
        Code = reader.GetStringValue("Code"),
        Name = reader.GetStringValue("Name"),
        Tagline = reader.GetNullableString("Tagline"),
        MonthlyPrice = reader.GetDecimalValue("MonthlyPrice"),
        YearlyPrice = reader.GetDecimalValue("YearlyPrice"),
        IsFeatured = reader.GetBoolValue("IsFeatured"),
        SortOrder = reader.GetInt32Value("SortOrder"),
        FeatureCount = reader.GetInt32Value("FeatureCount"),
        ActiveSubscriberCount = reader.GetInt32Value("ActiveSubscriberCount")
    };

    public static AdminPlanFeatureModel MapPlanFeature(SqlDataReader reader) => new()
    {
        PlanFeatureId = reader.GetGuidValue("PlanFeatureId"),
        PlanId = reader.GetGuidValue("PlanId"),
        FeatureText = reader.GetStringValue("FeatureText"),
        SortOrder = reader.GetByteValue("SortOrder"),
        IsHighlighted = reader.GetBoolValue("IsHighlighted")
    };

    public static AdminPlanEntitlementsModel MapPlanEntitlements(SqlDataReader reader) => new()
    {
        PlanId = reader.GetGuidValue("PlanId"),
        MaxActiveSplits = reader.GetNullableInt32("MaxActiveSplits"),
        MaxActiveDietPlans = reader.GetNullableInt32("MaxActiveDietPlans"),
        AllowAiGeneration = reader.GetBoolValue("AllowAiGeneration")
    };

    public static AdminSplitModel MapSplit(SqlDataReader reader) => new()
    {
        SplitId = reader.GetGuidValue("SplitId"),
        Name = reader.GetStringValue("Name"),
        Category = reader.GetStringValue("Category"),
        Level = reader.GetStringValue("Level"),
        DurationDays = reader.GetByteValue("DurationDays"),
        Description = reader.GetNullableString("Description"),
        HeroImageUrl = reader.GetNullableString("HeroImageUrl"),
        RecommendedGoal = reader.GetNullableString("RecommendedGoal"),
        IsSystemDefault = reader.GetBoolValue("IsSystemDefault"),
        Visibility = reader.GetStringValue("Visibility"),
        OwnerAdminUserId = reader.GetNullableGuid("OwnerAdminUserId"),
        OwnerUsername = reader.GetNullableString("OwnerUsername"),
        SortOrder = reader.GetInt32Value("SortOrder"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc"),
        DayCount = reader.GetInt32Value("DayCount"),
        ExerciseCount = reader.GetInt32Value("ExerciseCount"),
        ActiveUserCount = reader.GetInt32Value("ActiveUserCount"),
        AssignedUserCount = reader.GetInt32Value("AssignedUserCount")
    };

    public static AdminSplitAssignmentModel MapSplitAssignment(SqlDataReader reader) => new()
    {
        SplitId = reader.GetGuidValue("SplitId"),
        UserId = reader.GetGuidValue("UserId"),
        DisplayName = reader.GetNullableString("DisplayName"),
        Email = reader.GetNullableString("Email"),
        AccountTier = reader.GetStringValue("AccountTier"),
        AssignedAtUtc = reader.GetDateTimeValue("AssignedAtUtc"),
        AssignedByUsername = reader.GetNullableString("AssignedByUsername"),
        IsActive = reader.GetBoolValue("IsActive"),
        ActivePlanCode = reader.GetNullableString("ActivePlanCode"),
        BillingCycle = reader.GetNullableString("BillingCycle"),
        SubscriptionStatus = reader.GetNullableString("SubscriptionStatus")
    };

    public static AdminSplitDayModel MapSplitDay(SqlDataReader reader) => new()
    {
        SplitDayId = reader.GetGuidValue("SplitDayId"),
        SplitId = reader.GetGuidValue("SplitId"),
        DayIndex = reader.GetByteValue("DayIndex"),
        Title = reader.GetStringValue("Title"),
        FocusLabel = reader.GetNullableString("FocusLabel"),
        EstimatedMinutes = reader.GetInt16Value("EstimatedMinutes"),
        IsRestDay = reader.GetBoolValue("IsRestDay"),
        ExerciseCount = reader.GetInt32Value("ExerciseCount")
    };

    public static AdminSplitDayExerciseModel MapSplitDayExercise(SqlDataReader reader) => new()
    {
        SplitDayExerciseId = reader.GetGuidValue("SplitDayExerciseId"),
        SplitDayId = reader.GetGuidValue("SplitDayId"),
        DayIndex = reader.GetByteValue("DayIndex"),
        ExerciseId = reader.GetGuidValue("ExerciseId"),
        ExerciseName = reader.GetStringValue("ExerciseName"),
        MuscleGroup = reader.GetStringValue("MuscleGroup"),
        SortOrder = reader.GetByteValue("SortOrder"),
        TargetSets = reader.GetByteValue("TargetSets"),
        TargetRepsLow = reader.GetByteValue("TargetRepsLow"),
        TargetRepsHigh = reader.GetByteValue("TargetRepsHigh")
    };

    public static AdminDietPlanModel MapDietPlan(SqlDataReader reader) => new()
    {
        DietPlanId = reader.GetGuidValue("DietPlanId"),
        Name = reader.GetStringValue("Name"),
        Description = reader.GetNullableString("Description"),
        HeroImageUrl = reader.GetNullableString("HeroImageUrl"),
        PeriodType = reader.GetStringValue("PeriodType"),
        DurationDays = reader.GetByteValue("DurationDays"),
        IsSystemDefault = reader.GetBoolValue("IsSystemDefault"),
        Visibility = reader.GetStringValue("Visibility"),
        OwnerAdminUserId = reader.GetNullableGuid("OwnerAdminUserId"),
        OwnerUsername = reader.GetNullableString("OwnerUsername"),
        SortOrder = reader.GetInt32Value("SortOrder"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc"),
        DayCount = reader.GetInt32Value("DayCount"),
        MealCount = reader.GetInt32Value("MealCount"),
        ActiveUserCount = reader.GetInt32Value("ActiveUserCount"),
        AssignedUserCount = reader.GetInt32Value("AssignedUserCount")
    };

    public static AdminDietPlanAssignmentModel MapDietPlanAssignment(SqlDataReader reader) => new()
    {
        DietPlanId = reader.GetGuidValue("DietPlanId"),
        UserId = reader.GetGuidValue("UserId"),
        DisplayName = reader.GetNullableString("DisplayName"),
        Email = reader.GetNullableString("Email"),
        AccountTier = reader.GetStringValue("AccountTier"),
        AssignedAtUtc = reader.GetDateTimeValue("AssignedAtUtc"),
        AssignedByUsername = reader.GetNullableString("AssignedByUsername"),
        IsActive = reader.GetBoolValue("IsActive"),
        ActivePlanCode = reader.GetNullableString("ActivePlanCode"),
        BillingCycle = reader.GetNullableString("BillingCycle"),
        SubscriptionStatus = reader.GetNullableString("SubscriptionStatus")
    };

    public static AdminDietPlanDayModel MapDietPlanDay(SqlDataReader reader) => new()
    {
        DietPlanDayId = reader.GetGuidValue("DietPlanDayId"),
        DietPlanId = reader.GetGuidValue("DietPlanId"),
        DayIndex = reader.GetByteValue("DayIndex"),
        Title = reader.GetNullableString("Title"),
        MealCount = reader.GetInt32Value("MealCount")
    };

    public static AdminDietPlanMealModel MapDietPlanMeal(SqlDataReader reader) => new()
    {
        DietPlanMealId = reader.GetGuidValue("DietPlanMealId"),
        DietPlanDayId = reader.GetGuidValue("DietPlanDayId"),
        DayIndex = reader.GetByteValue("DayIndex"),
        MealType = reader.GetStringValue("MealType"),
        MealSuggestionId = reader.GetGuidValue("MealSuggestionId"),
        MealSuggestionTitle = reader.GetStringValue("MealSuggestionTitle"),
        CaloriesKcal = reader.GetInt16Value("CaloriesKcal"),
        ProteinG = reader.GetInt16Value("ProteinG"),
        CarbsG = reader.GetInt16Value("CarbsG"),
        FatsG = reader.GetInt16Value("FatsG"),
        SortOrder = reader.GetInt32Value("SortOrder")
    };

    public static AdminUserSummaryModel MapUserSummary(SqlDataReader reader) => new()
    {
        UserId = reader.GetGuidValue("UserId"),
        DisplayName = reader.GetNullableString("DisplayName"),
        Email = reader.GetNullableString("Email"),
        AccountTier = reader.GetStringValue("AccountTier"),
        IsActive = reader.GetBoolValue("IsActive"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc"),
        LastLoginAtUtc = reader.GetNullableDateTime("LastLoginAtUtc"),
        ActivePlanCode = reader.GetNullableString("ActivePlanCode"),
        BillingCycle = reader.GetNullableString("BillingCycle"),
        SubscriptionStatus = reader.GetNullableString("SubscriptionStatus"),
        ExpiresAtUtc = reader.GetNullableDateTime("ExpiresAtUtc")
    };

    /* --------------------------- client overview ----------------------------- */

    /// <summary>Onboarding answers, all AES-256-GCM ciphertext in UserProfiles
    /// (see UserProfileRowMapper). Null when the user never onboarded.</summary>
    public static AdminClientProfileModel? MapClientProfile(SqlDataReader reader, byte[] key)
    {
        var gender = reader.GetNullableBytes("Gender");
        var ageYears = reader.GetNullableBytes("AgeYears");
        var heightCm = reader.GetNullableBytes("HeightCm");
        var weightKg = reader.GetNullableBytes("WeightKg");
        var goal = reader.GetNullableBytes("Goal");
        var trainingDays = reader.GetNullableBytes("TrainingDaysPerWeek");
        var sessionMinutes = reader.GetNullableBytes("SessionDurationMinutes");
        var experience = reader.GetNullableBytes("TrainingExperience");
        var equipment = reader.GetNullableBytes("EquipmentAccess");
        var activity = reader.GetNullableBytes("DailyActivityLevel");

        if (gender is null && ageYears is null && heightCm is null && weightKg is null && goal is null
            && trainingDays is null && sessionMinutes is null && experience is null
            && equipment is null && activity is null)
        {
            return null;
        }

        return new AdminClientProfileModel
        {
            Gender = gender is null ? null : FieldCipher.DecryptString(gender, key),
            AgeYears = ageYears is null ? null : FieldCipher.DecryptInt(ageYears, key),
            HeightCm = heightCm is null ? null : FieldCipher.DecryptDecimal(heightCm, key),
            WeightKg = weightKg is null ? null : FieldCipher.DecryptDecimal(weightKg, key),
            Goal = goal is null ? null : FieldCipher.DecryptString(goal, key),
            TrainingDaysPerWeek = trainingDays is null ? null : FieldCipher.DecryptInt(trainingDays, key),
            SessionDurationMinutes = sessionMinutes is null ? null : FieldCipher.DecryptInt(sessionMinutes, key),
            TrainingExperience = experience is null ? null : FieldCipher.DecryptString(experience, key),
            EquipmentAccess = equipment is null ? null : FieldCipher.DecryptString(equipment, key),
            DailyActivityLevel = activity is null ? null : FieldCipher.DecryptString(activity, key)
        };
    }

    /// <summary>Nutrition targets (ciphertext, see MealPlanningRowMapper). Null when the user has none.</summary>
    public static AdminClientTargetsModel? MapClientTargets(SqlDataReader reader, byte[] key)
    {
        var calories = reader.GetNullableBytes("TargetCalories");
        if (calories is null)
        {
            return null;
        }

        return new AdminClientTargetsModel
        {
            TargetCalories = FieldCipher.DecryptInt(calories, key),
            TargetProteinG = FieldCipher.DecryptInt(reader.GetBytesValue("TargetProteinG"), key),
            TargetCarbsG = FieldCipher.DecryptInt(reader.GetBytesValue("TargetCarbsG"), key),
            TargetFatsG = FieldCipher.DecryptInt(reader.GetBytesValue("TargetFatsG"), key)
        };
    }

    public static AdminClientSessionModel MapClientSession(SqlDataReader reader) => new()
    {
        WorkoutSessionId = reader.GetGuidValue("WorkoutSessionId"),
        ScheduledDateUtc = reader.GetDateTimeValue("ScheduledDateUtc"),
        Status = reader.GetStringValue("Status"),
        CompletedAtUtc = reader.GetNullableDateTime("CompletedAtUtc"),
        DurationMinutes = reader.GetNullableInt16("DurationMinutes"),
        RpeScore = reader.GetNullableDecimal("RpeScore"),
        TonnageKg = reader.GetNullableDecimal("TonnageKg"),
        SplitDayTitle = reader.GetNullableString("SplitDayTitle"),
        SplitDayFocus = reader.GetNullableString("SplitDayFocus"),
        SetCount = reader.GetInt32Value("SetCount")
    };

    public static AdminClientSetModel MapClientSet(SqlDataReader reader) => new()
    {
        WorkoutSetLogId = reader.GetGuidValue("WorkoutSetLogId"),
        WorkoutSessionId = reader.GetGuidValue("WorkoutSessionId"),
        ExerciseName = reader.GetStringValue("ExerciseName"),
        MuscleGroup = reader.GetStringValue("MuscleGroup"),
        SetNumber = reader.GetByteValue("SetNumber"),
        WeightKg = reader.GetDecimalValue("WeightKg"),
        Reps = reader.GetInt16Value("Reps"),
        CompletedAtUtc = reader.GetDateTimeValue("CompletedAtUtc")
    };

    public static AdminClientMealModel MapClientMeal(SqlDataReader reader, byte[] key) => new()
    {
        MealLogId = reader.GetGuidValue("MealLogId"),
        LogDateUtc = reader.GetDateTimeValue("LogDateUtc"),
        MealType = reader.GetStringValue("MealType"),
        Title = FieldCipher.DecryptString(reader.GetBytesValue("Title"), key),
        CaloriesKcal = FieldCipher.DecryptInt(reader.GetBytesValue("CaloriesKcal"), key),
        ProteinG = FieldCipher.DecryptInt(reader.GetBytesValue("ProteinG"), key),
        CarbsG = FieldCipher.DecryptInt(reader.GetBytesValue("CarbsG"), key),
        FatsG = FieldCipher.DecryptInt(reader.GetBytesValue("FatsG"), key),
        Status = reader.GetStringValue("Status"),
        LoggedAtUtc = reader.GetNullableDateTime("LoggedAtUtc")
    };

    public static AdminClientBodyweightModel MapClientBodyweight(SqlDataReader reader, byte[] key) => new()
    {
        LoggedAtUtc = reader.GetDateTimeValue("LoggedAtUtc"),
        WeightKg = FieldCipher.DecryptDecimal(reader.GetBytesValue("WeightKg"), key)
    };

    public static AdminClientHydrationModel MapClientHydration(SqlDataReader reader) => new()
    {
        LogDateUtc = reader.GetDateTimeValue("LogDateUtc"),
        TotalMl = reader.GetInt32Value("TotalMl")
    };
}
