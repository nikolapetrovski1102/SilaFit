using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>
/// What the console can do once an operator is signed in: read and edit the
/// reference content, and (with the right permission) manage roles, operators and
/// the audit log.
///
/// Authorization is NOT enforced here - the API's policies decide who may call an
/// endpoint, from the same permission rows the database holds. By the time a method
/// on this service runs, the caller has already been allowed, and every write still
/// carries the actor so the change is attributed in SQL.
/// </summary>
public interface IAdminConsoleService
{
    /* ------------------------------- exercises ------------------------------ */
    Task<ServiceResult<List<AdminExerciseModel>>> GetExercisesAsync(CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> SaveExerciseAsync(AdminExerciseUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> DeleteExerciseAsync(Guid exerciseId, AdminActorModel actor, CancellationToken cancellationToken = default);

    /* --------------------------- meal suggestions ---------------------------- */
    Task<ServiceResult<List<AdminMealSuggestionModel>>> GetMealSuggestionsAsync(
        int? suggestedMonth,
        string? mealType,
        string? search,
        CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> SaveMealSuggestionAsync(AdminMealSuggestionUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> DeleteMealSuggestionAsync(Guid mealSuggestionId, AdminActorModel actor, CancellationToken cancellationToken = default);

    /* --------------------------------- plans -------------------------------- */
    Task<ServiceResult<List<AdminPlanModel>>> GetPlansAsync(CancellationToken cancellationToken = default);

    Task<ServiceResult<List<AdminPlanFeatureModel>>> GetPlanFeaturesAsync(Guid planId, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> SavePlanAsync(AdminPlanUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> DeletePlanAsync(Guid planId, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> SavePlanFeatureAsync(AdminPlanFeatureUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> DeletePlanFeatureAsync(Guid planFeatureId, AdminActorModel actor, CancellationToken cancellationToken = default);

    /* -------------------------------- splits -------------------------------- */
    Task<ServiceResult<List<AdminSplitModel>>> GetSplitsAsync(CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminSplitDetailModel>> GetSplitDetailAsync(Guid splitId, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> SaveSplitAsync(AdminSplitUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> DeleteSplitAsync(Guid splitId, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> SaveSplitDayAsync(AdminSplitDayUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> DeleteSplitDayAsync(Guid splitDayId, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> SaveSplitDayExerciseAsync(AdminSplitDayExerciseUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> DeleteSplitDayExerciseAsync(Guid splitDayExerciseId, AdminActorModel actor, CancellationToken cancellationToken = default);

    /* --------------------------------- users -------------------------------- */
    Task<ServiceResult<List<AdminUserSummaryModel>>> GetUsersAsync(string? search, int limit, CancellationToken cancellationToken = default);

    /* ------------------------ roles, operators, audit ----------------------- */
    Task<ServiceResult<List<AdminRoleModel>>> GetRolesAsync(CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminRolePermissionSetModel>> GetRolePermissionsAsync(string roleName, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> CreateRoleAsync(AdminRoleCreateRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> DeleteRoleAsync(string roleName, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> SetRolePermissionAsync(AdminRolePermissionRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<ServiceResult<List<AdminOperatorModel>>> GetOperatorsAsync(bool includeInactive, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> SetOperatorRoleAsync(AdminOperatorRoleRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> SetOperatorActiveAsync(AdminOperatorActiveRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<ServiceResult<List<AdminAuditEntryModel>>> GetRecentAuditAsync(int limit, CancellationToken cancellationToken = default);
}
