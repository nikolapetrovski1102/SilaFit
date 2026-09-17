using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>
/// The reference content the console edits - exercises, meal suggestions,
/// subscription plans and the split library - plus the read-only user list.
///
/// Reads and writes are separate procedures from the app's own (Exercises.sql,
/// MealPlanning.sql, Plans.sql, Splits.sql) because they serve a different caller
/// and return different shapes; the app never sees a usage count or a subscriber
/// count, and the console never sees a person's logs.
///
/// Every write takes an <see cref="AdminActorModel"/>: the audit row is written by
/// the procedure inside the same transaction as the change.
/// </summary>
public interface IAdminContentProvider
{
    Task<List<AdminExerciseModel>> GetExercisesAsync(CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertExerciseAsync(AdminExerciseUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteExerciseAsync(Guid exerciseId, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<List<AdminMealSuggestionModel>> GetMealSuggestionsAsync(
        int? suggestedMonth,
        string? mealType,
        string? search,
        CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertMealSuggestionAsync(AdminMealSuggestionUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteMealSuggestionAsync(Guid mealSuggestionId, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<List<AdminPlanModel>> GetPlansAsync(CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertPlanAsync(AdminPlanUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeletePlanAsync(Guid planId, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<List<AdminPlanFeatureModel>> GetPlanFeaturesAsync(Guid planId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertPlanFeatureAsync(AdminPlanFeatureUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeletePlanFeatureAsync(Guid planFeatureId, AdminActorModel actor, CancellationToken cancellationToken = default);

    /// <summary>Null when the plan has no entitlements row yet.</summary>
    Task<AdminPlanEntitlementsModel?> GetPlanEntitlementsAsync(Guid planId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertPlanEntitlementsAsync(AdminPlanEntitlementsUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<List<AdminSplitModel>> GetSplitsAsync(Guid? viewerAdminUserId, bool includeAll, CancellationToken cancellationToken = default);

    /// <summary>The split, its days and every prescription row - assembled from three procedures.</summary>
    Task<AdminSplitDetailModel?> GetSplitDetailAsync(Guid splitId, Guid? viewerAdminUserId, bool includeAll, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertSplitAsync(AdminSplitUpsertRequest request, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteSplitAsync(Guid splitId, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default);

    /// <summary>The clients a split is currently assigned to, with their plan context.</summary>
    Task<List<AdminSplitAssignmentModel>> GetSplitAssignmentsAsync(Guid splitId, CancellationToken cancellationToken = default);

    /// <summary>Grants one user visibility, optionally making the split their active program.</summary>
    Task<AdminMutationResultModel> AssignSplitAsync(AdminSplitAssignRequest request, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default);

    /// <summary>Revokes a user's access; clears it as their active split if it was.</summary>
    Task<AdminMutationResultModel> RemoveSplitAssignmentAsync(Guid splitId, Guid userId, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default);

    Task<List<AdminSplitDayModel>> GetSplitDaysAsync(Guid splitId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertSplitDayAsync(AdminSplitDayUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteSplitDayAsync(Guid splitDayId, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<List<AdminSplitDayExerciseModel>> GetSplitDayExercisesAsync(Guid splitId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertSplitDayExerciseAsync(AdminSplitDayExerciseUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteSplitDayExerciseAsync(Guid splitDayExerciseId, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<List<AdminUserSummaryModel>> GetUsersAsync(string? search, int limit, CancellationToken cancellationToken = default);

    /* ------------------------------- diet plans ------------------------------ */

    Task<List<AdminDietPlanModel>> GetDietPlansAsync(Guid? viewerAdminUserId, bool includeAll, CancellationToken cancellationToken = default);

    /// <summary>The plan, its days and every meal slot - assembled from three procedures.</summary>
    Task<AdminDietPlanDetailModel?> GetDietPlanDetailAsync(Guid dietPlanId, Guid? viewerAdminUserId, bool includeAll, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertDietPlanAsync(AdminDietPlanUpsertRequest request, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteDietPlanAsync(Guid dietPlanId, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default);

    /// <summary>The clients a plan is currently assigned to, with their plan context.</summary>
    Task<List<AdminDietPlanAssignmentModel>> GetDietPlanAssignmentsAsync(Guid dietPlanId, CancellationToken cancellationToken = default);

    /// <summary>Grants one user visibility, optionally making the plan their active diet plan.</summary>
    Task<AdminMutationResultModel> AssignDietPlanAsync(AdminDietPlanAssignRequest request, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default);

    /// <summary>Revokes a user's access; clears it as their active plan if it was.</summary>
    Task<AdminMutationResultModel> RemoveDietPlanAssignmentAsync(Guid dietPlanId, Guid userId, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken = default);

    Task<List<AdminDietPlanDayModel>> GetDietPlanDaysAsync(Guid dietPlanId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertDietPlanDayAsync(AdminDietPlanDayUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteDietPlanDayAsync(Guid dietPlanDayId, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<List<AdminDietPlanMealModel>> GetDietPlanMealsAsync(Guid dietPlanId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertDietPlanMealAsync(AdminDietPlanMealUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteDietPlanMealAsync(Guid dietPlanMealId, AdminActorModel actor, CancellationToken cancellationToken = default);
}
