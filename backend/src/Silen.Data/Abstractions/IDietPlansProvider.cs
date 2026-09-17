using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>App-facing diet-plan reads/writes - the meal-planning equivalent of
/// <see cref="ISplitsProvider"/>. Browse/detail come from MealPlanning.sql;
/// owned-plan writes come from UserDietPlans.sql.</summary>
public interface IDietPlansProvider
{
    /// <param name="userId">The caller's id, so private/shared plans are filtered to the
    /// assignments that mention them; null (a guest) sees only the public catalogue.</param>
    Task<List<DietPlanModel>> GetAllAsync(Guid? userId, CancellationToken cancellationToken = default);

    /// <param name="userId">Same visibility filter as <see cref="GetAllAsync"/>; an
    /// invisible plan comes back as a null header rather than a readable detail.</param>
    Task<(DietPlanModel? Plan, List<DietPlanDayModel> Days, List<DietPlanMealModel> Meals)> GetDetailAsync(
        Guid dietPlanId, Guid? userId, CancellationToken cancellationToken = default);

    /* --------------------------- user-owned diet plans --------------------------- */

    /// <summary>Every plan this user has built themselves (usp_UserDietPlans_GetOwned).</summary>
    Task<List<DietPlanModel>> GetOwnedAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertUserDietPlanAsync(UserDietPlanUpsertRequest request, Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Marks an AI-generated plan permanent (usp_UserDietPlan_Keep) - a no-op, not an
    /// error, when the plan isn't AI-generated or is already kept.</summary>
    Task<AdminMutationResultModel> KeepUserDietPlanAsync(Guid dietPlanId, Guid userId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteUserDietPlanAsync(Guid dietPlanId, Guid userId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertUserDietPlanDayAsync(UserDietPlanDayUpsertRequest request, Guid userId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteUserDietPlanDayAsync(Guid dietPlanDayId, Guid userId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertUserDietPlanMealAsync(UserDietPlanMealUpsertRequest request, Guid userId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteUserDietPlanMealAsync(Guid dietPlanMealId, Guid userId, CancellationToken cancellationToken = default);

    /// <summary>The plan currently active for this user, or null when none is active
    /// (usp_UserActiveDietPlan_Get). The caller loads its days/meals via
    /// <see cref="GetDetailAsync"/>.</summary>
    Task<ActiveDietPlanModel?> GetActiveAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Sets a user's current diet plan (usp_UserActiveDietPlan_Set), the diet-plan
    /// counterpart of <see cref="ISplitsProvider.SetActiveAsync"/>. Called by the app's
    /// activate endpoint and by Silen.Tools.WeeklyPlanGeneration for users with
    /// AutoActivateAiPlans on.</summary>
    Task SetActiveDietPlanAsync(Guid userId, Guid dietPlanId, CancellationToken cancellationToken = default);
}
