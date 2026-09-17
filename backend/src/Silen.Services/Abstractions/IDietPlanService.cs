using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>App-facing diet plans - the meal-planning equivalent of <see cref="ISplitService"/>.
/// "Activate" is now wired: the Nutrition screen reads the user's active plan and can
/// switch it to any visible plan (see <see cref="GetActiveAsync"/> / <see cref="ActivateAsync"/>).</summary>
public interface IDietPlanService
{
    /// <param name="userId">The caller's id if authenticated (guests included), so a
    /// private/shared plan the user is not assigned to is filtered out by the procedure.</param>
    Task<ServiceResult<List<DietPlanModel>>> GetAllAsync(Guid? userId, CancellationToken cancellationToken = default);

    /// <param name="userId">Same visibility filter as <see cref="GetAllAsync"/>; an
    /// invisible plan is treated as not found rather than readable.</param>
    Task<ServiceResult<DietPlanDetailDto>> GetDetailAsync(Guid dietPlanId, Guid? userId, CancellationToken cancellationToken = default);

    /// <summary>The caller's currently active diet plan, with its full days/meals, or
    /// null when none is active. Backs the Nutrition screen's "active plan" section.</summary>
    Task<ServiceResult<DietPlanDetailDto?>> GetActiveAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Makes any plan visible to the caller their active plan.</summary>
    Task<ServiceResult<AdminWriteResultDto>> ActivateAsync(Guid userId, Guid dietPlanId, CancellationToken cancellationToken = default);

    /* ----------------------------- user-owned diet plans ----------------------------- */

    /// <summary>Every plan this user has built themselves via the in-app builder.</summary>
    Task<ServiceResult<List<DietPlanModel>>> GetMyPlansAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Creates a new plan (null DietPlanId) or updates one this user owns.</summary>
    Task<ServiceResult<AdminWriteResultDto>> CreateOrUpdateMyPlanAsync(Guid userId, UserDietPlanUpsertRequest request, CancellationToken cancellationToken = default);

    /// <summary>Refused for a plan this user doesn't own.</summary>
    Task<ServiceResult<AdminWriteResultDto>> DeleteMyPlanAsync(Guid userId, Guid dietPlanId, CancellationToken cancellationToken = default);

    /// <summary>Marks an AI-generated plan as permanent: the next Sunday run creates a fresh
    /// plan for this user instead of overwriting this one. A no-op for a plan that isn't
    /// AI-generated or is already kept.</summary>
    Task<ServiceResult<AdminWriteResultDto>> KeepMyPlanAsync(Guid userId, Guid dietPlanId, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> SaveMyPlanDayAsync(Guid userId, UserDietPlanDayUpsertRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> DeleteMyPlanDayAsync(Guid userId, Guid dietPlanDayId, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> SaveMyPlanMealAsync(Guid userId, UserDietPlanMealUpsertRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> DeleteMyPlanMealAsync(Guid userId, Guid dietPlanMealId, CancellationToken cancellationToken = default);
}
