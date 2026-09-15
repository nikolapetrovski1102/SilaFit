using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>
/// What the console can do once an operator is signed in: read and edit the
/// reference content - exercises, meal suggestions, subscription plans and the
/// split library - plus the read-only user list.
///
/// Same shape as <see cref="IAdminRbacService"/> and for the same reason: this
/// codebase has no cookie-based ASP.NET authentication scheme, so there is no
/// declarative policy an [Authorize] attribute could check. Every method here
/// takes the raw session cookie value and resolves both "who is this" and "may
/// they do this" from it via <c>AdminPermissionGuard</c>, against the exact
/// content.* permission named in its own summary - so a controller action is
/// always a one-liner that trusts the cookie, never a bearer token, and a
/// revoked permission stops working on the very next request.
/// </summary>
public interface IAdminConsoleService
{
    /* ------------------------------- exercises ------------------------------ */

    /// <summary>Requires content.exercises.read.</summary>
    Task<ServiceResult<List<AdminExerciseModel>>> GetExercisesAsync(string? sessionToken, CancellationToken cancellationToken = default);

    /// <summary>Creates or updates an exercise. Requires content.exercises.write.</summary>
    Task<ServiceResult<AdminWriteResultDto>> SaveExerciseAsync(string? sessionToken, AdminExerciseUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Refused while any split day still references the exercise. Requires content.exercises.write.</summary>
    Task<ServiceResult<AdminWriteResultDto>> DeleteExerciseAsync(string? sessionToken, Guid exerciseId, string? clientIp, CancellationToken cancellationToken = default);

    /* --------------------------- meal suggestions ---------------------------- */

    /// <summary>Requires content.suggestions.read.</summary>
    Task<ServiceResult<List<AdminMealSuggestionModel>>> GetMealSuggestionsAsync(
        string? sessionToken,
        int? suggestedMonth,
        string? mealType,
        string? search,
        CancellationToken cancellationToken = default);

    /// <summary>Requires content.suggestions.write.</summary>
    Task<ServiceResult<AdminWriteResultDto>> SaveMealSuggestionAsync(string? sessionToken, AdminMealSuggestionUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Requires content.suggestions.write.</summary>
    Task<ServiceResult<AdminWriteResultDto>> DeleteMealSuggestionAsync(string? sessionToken, Guid mealSuggestionId, string? clientIp, CancellationToken cancellationToken = default);

    /* --------------------------------- plans -------------------------------- */

    /// <summary>Requires content.plans.read.</summary>
    Task<ServiceResult<List<AdminPlanModel>>> GetPlansAsync(string? sessionToken, CancellationToken cancellationToken = default);

    /// <summary>Requires content.plans.read.</summary>
    Task<ServiceResult<List<AdminPlanFeatureModel>>> GetPlanFeaturesAsync(string? sessionToken, Guid planId, CancellationToken cancellationToken = default);

    /// <summary>Requires content.plans.write.</summary>
    Task<ServiceResult<AdminWriteResultDto>> SavePlanAsync(string? sessionToken, AdminPlanUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Refused while the plan still has active subscribers. Requires content.plans.write.</summary>
    Task<ServiceResult<AdminWriteResultDto>> DeletePlanAsync(string? sessionToken, Guid planId, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Requires content.plans.write.</summary>
    Task<ServiceResult<AdminWriteResultDto>> SavePlanFeatureAsync(string? sessionToken, AdminPlanFeatureUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Requires content.plans.write.</summary>
    Task<ServiceResult<AdminWriteResultDto>> DeletePlanFeatureAsync(string? sessionToken, Guid planFeatureId, string? clientIp, CancellationToken cancellationToken = default);

    /* -------------------------------- splits -------------------------------- */

    /// <summary>Requires content.splits.read. Without content.splits.manage_all the
    /// caller only sees the splits they own, plus the shipped system splits.</summary>
    Task<ServiceResult<List<AdminSplitModel>>> GetSplitsAsync(string? sessionToken, CancellationToken cancellationToken = default);

    /// <summary>The split, its days and every prescription row. Requires content.splits.read.</summary>
    Task<ServiceResult<AdminSplitDetailModel>> GetSplitDetailAsync(string? sessionToken, Guid splitId, CancellationToken cancellationToken = default);

    /// <summary>Requires content.splits.write. A trainer may only change a split they own;
    /// content.splits.manage_all lifts that (and is required for system splits).</summary>
    Task<ServiceResult<AdminWriteResultDto>> SaveSplitAsync(string? sessionToken, AdminSplitUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Refused while any user has the split active, and refused for a split
    /// owned by another trainer. Requires content.splits.write.</summary>
    Task<ServiceResult<AdminWriteResultDto>> DeleteSplitAsync(string? sessionToken, Guid splitId, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>The clients one split is assigned to, with plan context. Requires content.splits.read.</summary>
    Task<ServiceResult<List<AdminSplitAssignmentModel>>> GetSplitAssignmentsAsync(string? sessionToken, Guid splitId, CancellationToken cancellationToken = default);

    /// <summary>Assigns a split to one user, optionally as their active program.
    /// Requires content.splits.assign; ownership is enforced on top.</summary>
    Task<ServiceResult<AdminWriteResultDto>> AssignSplitAsync(string? sessionToken, AdminSplitAssignRequest request, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Revokes a user's access to a split. Requires content.splits.assign;
    /// ownership is enforced on top.</summary>
    Task<ServiceResult<AdminWriteResultDto>> RemoveSplitAssignmentAsync(string? sessionToken, Guid splitId, Guid userId, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Requires content.splits.write.</summary>
    Task<ServiceResult<AdminWriteResultDto>> SaveSplitDayAsync(string? sessionToken, AdminSplitDayUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Requires content.splits.write.</summary>
    Task<ServiceResult<AdminWriteResultDto>> DeleteSplitDayAsync(string? sessionToken, Guid splitDayId, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Requires content.splits.write.</summary>
    Task<ServiceResult<AdminWriteResultDto>> SaveSplitDayExerciseAsync(string? sessionToken, AdminSplitDayExerciseUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Requires content.splits.write.</summary>
    Task<ServiceResult<AdminWriteResultDto>> DeleteSplitDayExerciseAsync(string? sessionToken, Guid splitDayExerciseId, string? clientIp, CancellationToken cancellationToken = default);

    /* --------------------------------- users -------------------------------- */

    /// <summary>Requires users.read.</summary>
    Task<ServiceResult<List<AdminUserSummaryModel>>> GetUsersAsync(string? sessionToken, string? search, int limit, CancellationToken cancellationToken = default);

    /// <summary>
    /// Regenerates one user's logs with a month of mock history and puts them on the
    /// chosen tier profile, so the monthly overview can be exercised on demand.
    /// Requires users.mock_data (granted to super-admin only) and is destructive to
    /// the target user's existing workouts, meals, hydration and bodyweight.
    /// </summary>
    Task<ServiceResult<AdminWriteResultDto>> SeedUserMockDataAsync(
        string? sessionToken,
        AdminMockDataRequest request,
        string? clientIp,
        CancellationToken cancellationToken = default);
}
