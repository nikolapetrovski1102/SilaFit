namespace Silen.Common.Models;

/// <summary>
/// The Outcome column every admin write procedure returns, mapped straight from
/// SQL. Because the procedures decide "may this row be deleted" (they are the only
/// code that can do it inside a transaction), the service layer's job is to
/// translate these codes into HTTP rather than to re-derive the rules.
/// </summary>
public enum AdminWriteOutcome
{
    Success = 0,

    /// <summary>The row (or the referenced parent) does not exist.</summary>
    NotFound = 1,

    /// <summary>Allowed by permission, refused by state: still in use, duplicate, or built-in.</summary>
    Conflict = 2,

    /// <summary>The input itself is unusable (blank name, out-of-range month, inverted reps...).</summary>
    Rejected = 3
}

/// <summary>Row shape of every admin mutation procedure: outcome, affected row, and a human-readable reason.</summary>
public sealed class AdminMutationResultModel
{
    public int Outcome { get; set; }
    public Guid? EntityId { get; set; }
    public string? Detail { get; set; }

    public AdminWriteOutcome Result => (AdminWriteOutcome)Outcome;
}

/// <summary>A role and how much it is used - the console's role list.</summary>
public sealed class AdminRoleModel
{
    public Guid RoleId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public bool IsSystemRole { get; set; }
    public int PermissionCount { get; set; }
    public int OperatorCount { get; set; }
}

/// <summary>One role's granted permissions, from usp_Admin_RolePermissions_GetForRole.</summary>
public sealed class AdminRolePermissionSetModel
{
    public string RoleName { get; set; } = string.Empty;
    public bool IsSystemRole { get; set; }
    public List<string> Permissions { get; set; } = [];
}

/// <summary>A console operator: the account, the role behind it, and its live sessions.</summary>
public sealed class AdminOperatorModel
{
    public Guid AdminUserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public Guid? RoleId { get; set; }
    public string? RoleName { get; set; }
    public bool IsActive { get; set; }
    public DateTime? LastLoginAtUtc { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public int ActiveSessionCount { get; set; }
    public string? Email { get; set; }
    public DateTime? EmailConfirmedAtUtc { get; set; }
}

/// <summary>One line of the audit trail.</summary>
public sealed class AdminAuditEntryModel
{
    public Guid AuditId { get; set; }
    public Guid? AdminUserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Action { get; set; } = string.Empty;
    public string EntityType { get; set; } = string.Empty;
    public string? EntityId { get; set; }
    public string? Summary { get; set; }
    public string? CreatedFromIp { get; set; }
    public DateTime CreatedAtUtc { get; set; }
}

/// <summary>An exercise plus how many split-day rows reference it (the delete guard the console shows).</summary>
public sealed class AdminExerciseModel
{
    public Guid ExerciseId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string MuscleGroup { get; set; } = string.Empty;
    public string? EquipmentType { get; set; }
    public bool IsCompound { get; set; }
    public string? DemoVideoUrl { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public int UsageCount { get; set; }
}

/// <summary>A meal suggestion. IsSystemDefault marks shipped seed content versus something an operator wrote.</summary>
public sealed class AdminMealSuggestionModel
{
    public Guid MealSuggestionId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string MealType { get; set; } = string.Empty;
    public string? Description { get; set; }
    public int CaloriesKcal { get; set; }
    public int ProteinG { get; set; }
    public int CarbsG { get; set; }
    public int FatsG { get; set; }
    public int? SuggestedMonth { get; set; }
    public bool IsSystemDefault { get; set; }
    public int SortOrder { get; set; }
    public DateTime CreatedAtUtc { get; set; }
}

/// <summary>A subscription plan with its feature count and how many subscribers it currently has.</summary>
public sealed class AdminPlanModel
{
    public Guid PlanId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Tagline { get; set; }
    public decimal MonthlyPrice { get; set; }
    public decimal YearlyPrice { get; set; }
    public bool IsFeatured { get; set; }
    public int SortOrder { get; set; }
    public int FeatureCount { get; set; }
    public int ActiveSubscriberCount { get; set; }
}

public sealed class AdminPlanFeatureModel
{
    public Guid PlanFeatureId { get; set; }
    public Guid PlanId { get; set; }
    public string FeatureText { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public bool IsHighlighted { get; set; }
}

/// <summary>One plan's entitlements as the console edits them. Null on a limit means unlimited.</summary>
public sealed class AdminPlanEntitlementsModel
{
    public Guid PlanId { get; set; }
    public int? MaxActiveSplits { get; set; }
    public int? MaxActiveDietPlans { get; set; }
    public bool AllowAiGeneration { get; set; }
}

/// <summary>A split with the counts that decide whether it is safe to edit or delete.</summary>
public sealed class AdminSplitModel
{
    public Guid SplitId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Level { get; set; } = string.Empty;
    public int DurationDays { get; set; }
    public string? Description { get; set; }
    public string? HeroImageUrl { get; set; }
    public string? RecommendedGoal { get; set; }
    public bool IsSystemDefault { get; set; }
    public int SortOrder { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public int DayCount { get; set; }
    public int ExerciseCount { get; set; }
    public int ActiveUserCount { get; set; }

    /// <summary>'Private' | 'Public' | 'Shared' - see WorkoutSplits.Visibility.</summary>
    public string Visibility { get; set; } = "Public";

    /// <summary>The console operator who authored the split; null for shipped/system content.</summary>
    public Guid? OwnerAdminUserId { get; set; }

    public string? OwnerUsername { get; set; }

    /// <summary>How many app users this split has been assigned to.</summary>
    public int AssignedUserCount { get; set; }

    /// <summary>
    /// Computed by the service per request: true when the signed-in operator may
    /// edit/delete/assign this split (owns it, or holds content.splits.manage_all).
    /// The console uses it to hide mutation buttons rather than letting a trainer
    /// click one and eat a 409.
    /// </summary>
    public bool CanManage { get; set; }
}

/// <summary>One client a split has been assigned to, with just enough account context
/// (plan/status) for the trainer to see who is actually paying - never any logs.</summary>
public sealed class AdminSplitAssignmentModel
{
    public Guid SplitId { get; set; }
    public Guid UserId { get; set; }
    public string? DisplayName { get; set; }
    public string? Email { get; set; }
    public string AccountTier { get; set; } = string.Empty;
    public DateTime AssignedAtUtc { get; set; }
    public string? AssignedByUsername { get; set; }

    /// <summary>True when this split is currently the user's active program.</summary>
    public bool IsActive { get; set; }

    public string? ActivePlanCode { get; set; }
    public string? BillingCycle { get; set; }
    public string? SubscriptionStatus { get; set; }
}

public sealed class AdminSplitDayModel
{
    public Guid SplitDayId { get; set; }
    public Guid SplitId { get; set; }
    public int DayIndex { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? FocusLabel { get; set; }
    public int EstimatedMinutes { get; set; }
    public bool IsRestDay { get; set; }
    public int ExerciseCount { get; set; }
}

/// <summary>
/// One prescription line, with the exercise name joined in so a day can be rendered
/// without a lookup per exercise.
/// </summary>
public sealed class AdminSplitDayExerciseModel
{
    public Guid SplitDayExerciseId { get; set; }
    public Guid SplitDayId { get; set; }
    public int DayIndex { get; set; }
    public Guid ExerciseId { get; set; }
    public string ExerciseName { get; set; } = string.Empty;
    public string MuscleGroup { get; set; } = string.Empty;
    public int SortOrder { get; set; }
    public int TargetSets { get; set; }
    public int TargetRepsLow { get; set; }
    public int TargetRepsHigh { get; set; }
}

/// <summary>Everything the split editor needs for one split, assembled from three procedures.</summary>
public sealed class AdminSplitDetailModel
{
    public AdminSplitModel Split { get; set; } = new();
    public List<AdminSplitDayModel> Days { get; set; } = [];
    public List<AdminSplitDayExerciseModel> DayExercises { get; set; } = [];
}

/// <summary>A diet plan with the counts that decide whether it is safe to edit or delete.
/// Structural clone of AdminSplitModel for the meal-planning equivalent.</summary>
public sealed class AdminDietPlanModel
{
    public Guid DietPlanId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? HeroImageUrl { get; set; }
    public string PeriodType { get; set; } = "Weekly";
    public int DurationDays { get; set; }
    public bool IsSystemDefault { get; set; }
    public int SortOrder { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public int DayCount { get; set; }
    public int MealCount { get; set; }
    public int ActiveUserCount { get; set; }

    /// <summary>'Private' | 'Public' | 'Shared' - see DietPlans.Visibility.</summary>
    public string Visibility { get; set; } = "Public";

    /// <summary>The console operator who authored the plan; null for shipped/system content.</summary>
    public Guid? OwnerAdminUserId { get; set; }

    public string? OwnerUsername { get; set; }

    /// <summary>How many app users this plan has been assigned to.</summary>
    public int AssignedUserCount { get; set; }

    /// <summary>
    /// Computed by the service per request: true when the signed-in operator may
    /// edit/delete/assign this plan (owns it, or holds content.diet_plans.manage_all).
    /// </summary>
    public bool CanManage { get; set; }
}

/// <summary>One client a diet plan has been assigned to - clone of AdminSplitAssignmentModel.</summary>
public sealed class AdminDietPlanAssignmentModel
{
    public Guid DietPlanId { get; set; }
    public Guid UserId { get; set; }
    public string? DisplayName { get; set; }
    public string? Email { get; set; }
    public string AccountTier { get; set; } = string.Empty;
    public DateTime AssignedAtUtc { get; set; }
    public string? AssignedByUsername { get; set; }

    /// <summary>True when this plan is currently the user's active plan.</summary>
    public bool IsActive { get; set; }

    public string? ActivePlanCode { get; set; }
    public string? BillingCycle { get; set; }
    public string? SubscriptionStatus { get; set; }
}

public sealed class AdminDietPlanDayModel
{
    public Guid DietPlanDayId { get; set; }
    public Guid DietPlanId { get; set; }
    public int DayIndex { get; set; }
    public string? Title { get; set; }
    public int MealCount { get; set; }
}

/// <summary>
/// One meal slot, with the referenced MealSuggestions row's title/macros joined in
/// so a day can be rendered without a lookup per slot.
/// </summary>
public sealed class AdminDietPlanMealModel
{
    public Guid DietPlanMealId { get; set; }
    public Guid DietPlanDayId { get; set; }
    public int DayIndex { get; set; }
    public string MealType { get; set; } = string.Empty;
    public Guid MealSuggestionId { get; set; }
    public string MealSuggestionTitle { get; set; } = string.Empty;
    public int CaloriesKcal { get; set; }
    public int ProteinG { get; set; }
    public int CarbsG { get; set; }
    public int FatsG { get; set; }
    public int SortOrder { get; set; }
}

/// <summary>Everything the diet plan editor needs for one plan, assembled from three procedures.</summary>
public sealed class AdminDietPlanDetailModel
{
    public AdminDietPlanModel Plan { get; set; } = new();
    public List<AdminDietPlanDayModel> Days { get; set; } = [];
    public List<AdminDietPlanMealModel> Meals { get; set; } = [];
}

/// <summary>
/// An app user as the console may see them: tier, join date and current
/// subscription. Deliberately excludes everything the app stores about a person
/// (logs, bodyweight, nutrition) - reading those is a much bigger decision than
/// reading who signed up.
/// </summary>
public sealed class AdminUserSummaryModel
{
    public Guid UserId { get; set; }
    public string? DisplayName { get; set; }
    public string? Email { get; set; }
    public string AccountTier { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public DateTime? LastLoginAtUtc { get; set; }
    public string? ActivePlanCode { get; set; }
    public string? BillingCycle { get; set; }
    public string? SubscriptionStatus { get; set; }
    public DateTime? ExpiresAtUtc { get; set; }
}

/// <summary>
/// One client's logged data as the console shows it to an operator who may see
/// clients (trainer/super-admin/analyst). Account/onboarding answers plus the
/// last <see cref="FromDateUtc"/>-<see cref="ToDateUtc"/> window of training,
/// meals, bodyweight and hydration. Encrypted columns are decrypted in the
/// provider, never in SQL.
/// </summary>
public sealed class AdminClientOverviewModel
{
    public AdminUserSummaryModel Account { get; set; } = new();

    /// <summary>Null when the user never completed onboarding (no UserProfiles row).</summary>
    public AdminClientProfileModel? Profile { get; set; }

    public AdminClientActiveSplitModel? ActiveSplit { get; set; }
    public AdminClientActiveDietPlanModel? ActiveDietPlan { get; set; }

    public AdminClientTargetsModel? Targets { get; set; }

    public DateTime FromDateUtc { get; set; }
    public DateTime ToDateUtc { get; set; }

    public AdminClientSummaryModel Summary { get; set; } = new();
    public List<AdminClientSessionModel> Sessions { get; set; } = [];
    public List<AdminClientMealModel> Meals { get; set; } = [];
    public List<AdminClientBodyweightModel> Bodyweight { get; set; } = [];
    public List<AdminClientHydrationModel> Hydration { get; set; } = [];
}

public sealed class AdminClientProfileModel
{
    public string? Gender { get; set; }
    public int? AgeYears { get; set; }
    public decimal? HeightCm { get; set; }
    public decimal? WeightKg { get; set; }
    public string? Goal { get; set; }
    public int? TrainingDaysPerWeek { get; set; }
    public int? SessionDurationMinutes { get; set; }
    public string? TrainingExperience { get; set; }
    public string? EquipmentAccess { get; set; }
    public string? DailyActivityLevel { get; set; }
}

public sealed class AdminClientTargetsModel
{
    public int TargetCalories { get; set; }
    public int TargetProteinG { get; set; }
    public int TargetCarbsG { get; set; }
    public int TargetFatsG { get; set; }
}

public sealed class AdminClientActiveSplitModel
{
    public Guid SplitId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Level { get; set; } = string.Empty;
    public DateTime ActivatedAtUtc { get; set; }
}

public sealed class AdminClientActiveDietPlanModel
{
    public Guid DietPlanId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string PeriodType { get; set; } = string.Empty;
    public DateTime ActivatedAtUtc { get; set; }
}

public sealed class AdminClientSummaryModel
{
    public int CompletedSessions { get; set; }
    public int ScheduledSessions { get; set; }
    public decimal TotalTonnageKg { get; set; }
    public decimal AvgRpe { get; set; }
    public int TotalSets { get; set; }
    public int LoggedMeals { get; set; }
    public int LoggedMealDays { get; set; }
    public int TotalDaysInRange { get; set; }
    public decimal? AvgCaloriesLogged { get; set; }
    public decimal? StartWeightKg { get; set; }
    public decimal? EndWeightKg { get; set; }
    public int AvgHydrationMl { get; set; }
}

public sealed class AdminClientSessionModel
{
    public Guid WorkoutSessionId { get; set; }
    public DateTime ScheduledDateUtc { get; set; }
    public string Status { get; set; } = string.Empty;
    public DateTime? CompletedAtUtc { get; set; }
    public int? DurationMinutes { get; set; }
    public decimal? RpeScore { get; set; }
    public decimal? TonnageKg { get; set; }
    public string? SplitDayTitle { get; set; }
    public string? SplitDayFocus { get; set; }
    public int SetCount { get; set; }
    public List<AdminClientSetModel> Sets { get; set; } = [];
}

public sealed class AdminClientSetModel
{
    public Guid WorkoutSetLogId { get; set; }

    /// <summary>Used to attach the set to its session in the provider; not part
    /// of the console's display model beyond that.</summary>
    public Guid WorkoutSessionId { get; set; }

    public string ExerciseName { get; set; } = string.Empty;
    public string MuscleGroup { get; set; } = string.Empty;
    public int SetNumber { get; set; }
    public decimal WeightKg { get; set; }
    public int Reps { get; set; }
    public DateTime CompletedAtUtc { get; set; }
}

public sealed class AdminClientMealModel
{
    public Guid MealLogId { get; set; }
    public DateTime LogDateUtc { get; set; }
    public string MealType { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public int CaloriesKcal { get; set; }
    public int ProteinG { get; set; }
    public int CarbsG { get; set; }
    public int FatsG { get; set; }
    public string Status { get; set; } = string.Empty;
    public DateTime? LoggedAtUtc { get; set; }
}

public sealed class AdminClientBodyweightModel
{
    public DateTime LoggedAtUtc { get; set; }
    public decimal WeightKg { get; set; }
}

public sealed class AdminClientHydrationModel
{
    public DateTime LogDateUtc { get; set; }
    public int TotalMl { get; set; }
}
