using Microsoft.Data.SqlClient;
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
        ActiveSessionCount = reader.GetInt32Value("ActiveSessionCount")
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
}
