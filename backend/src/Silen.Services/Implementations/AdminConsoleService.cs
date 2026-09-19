using Silen.Common.Authorization;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IAdminConsoleService"/>
public sealed class AdminConsoleService(
    IAdminProvider adminProvider,
    IAdminRbacProvider adminRbacProvider,
    IAdminContentProvider contentProvider,
    IMockDataSeeder mockDataSeeder,
    IImageUploadService imageUploadService) : IAdminConsoleService
{
    /* ------------------------------- exercises ------------------------------ */

    public Task<ServiceResult<List<AdminExerciseModel>>> GetExercisesAsync(string? sessionToken, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            // The split-day editor populates its exercise picker from this read, so
            // anyone who may edit splits needs it too, not only exercise readers.
            await RequireAnyAsync(
                sessionToken,
                [AdminPermissions.ExercisesRead, AdminPermissions.SplitsWrite],
                cancellationToken);

            return await contentProvider.GetExercisesAsync(cancellationToken);
        });

    public Task<ServiceResult<AdminWriteResultDto>> SaveExerciseAsync(string? sessionToken, AdminExerciseUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.ExercisesWrite, clientIp, cancellationToken);

            var name = request.Name.Trim();
            if (string.IsNullOrWhiteSpace(name))
            {
                throw new ValidationException("Exercise upsert called with a blank name.", "Give the exercise a name.");
            }
            AdminContentFieldRules.ThrowIfUnknown(request.MuscleGroup, AdminContentFieldRules.MuscleGroups, "muscle group");
            request.Name = name;

            var mutation = await contentProvider.UpsertExerciseAsync(request, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, $"Exercise '{name}' saved.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteExerciseAsync(string? sessionToken, Guid exerciseId, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.ExercisesWrite, clientIp, cancellationToken);

            var mutation = await contentProvider.DeleteExerciseAsync(exerciseId, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Exercise deleted.");
        });

    /* --------------------------------- images -------------------------------- */

    public Task<ServiceResult<AdminImageUploadResultDto>> UploadImageAsync(string? sessionToken, ImageUploadRequest upload, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await RequireAsync(sessionToken, AdminPermissions.SplitsWrite, clientIp, cancellationToken);

            var url = await imageUploadService.SaveAsync(upload, cancellationToken);
            return new AdminImageUploadResultDto { Url = url };
        });

    /* --------------------------- meal suggestions ---------------------------- */

    public Task<ServiceResult<List<AdminMealSuggestionModel>>> GetMealSuggestionsAsync(
        string? sessionToken,
        int? suggestedMonth,
        string? mealType,
        string? search,
        CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            // The diet-plan day editor populates its meal-slot picker from this read,
            // so anyone who may edit diet plans needs it too, not only suggestion readers.
            await RequireAnyAsync(
                sessionToken,
                [AdminPermissions.SuggestionsRead, AdminPermissions.DietPlansWrite],
                cancellationToken);

            if (suggestedMonth is < 1 or > 12)
            {
                throw new ValidationException($"Meal suggestions listed with out-of-range month {suggestedMonth}.", "Month must be between 1 and 12.");
            }
            AdminContentFieldRules.ThrowIfUnknownWhenSet(mealType, AdminContentFieldRules.MealTypes, "meal type");

            return await contentProvider.GetMealSuggestionsAsync(suggestedMonth, mealType, search, cancellationToken);
        });

    public Task<ServiceResult<AdminWriteResultDto>> SaveMealSuggestionAsync(string? sessionToken, AdminMealSuggestionUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.SuggestionsWrite, clientIp, cancellationToken);

            var title = request.Title.Trim();
            if (string.IsNullOrWhiteSpace(title))
            {
                throw new ValidationException("Meal suggestion upsert called with a blank title.", "Give the suggestion a title.");
            }
            AdminContentFieldRules.ThrowIfUnknown(request.MealType, AdminContentFieldRules.MealTypes, "meal type");
            if (request.SuggestedMonth is < 1 or > 12)
            {
                throw new ValidationException($"Meal suggestion upsert called with out-of-range month {request.SuggestedMonth}.", "Suggested month must be between 1 and 12.");
            }
            request.Title = title;

            var mutation = await contentProvider.UpsertMealSuggestionAsync(request, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, $"Suggestion '{title}' saved.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteMealSuggestionAsync(string? sessionToken, Guid mealSuggestionId, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.SuggestionsWrite, clientIp, cancellationToken);

            var mutation = await contentProvider.DeleteMealSuggestionAsync(mealSuggestionId, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Suggestion deleted.");
        });

    /* --------------------------------- plans -------------------------------- */

    public Task<ServiceResult<List<AdminPlanModel>>> GetPlansAsync(string? sessionToken, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await RequireAsync(sessionToken, AdminPermissions.PlansRead, null, cancellationToken);
            return await contentProvider.GetPlansAsync(cancellationToken);
        });

    public Task<ServiceResult<List<AdminPlanFeatureModel>>> GetPlanFeaturesAsync(string? sessionToken, Guid planId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await RequireAsync(sessionToken, AdminPermissions.PlansRead, null, cancellationToken);
            return await contentProvider.GetPlanFeaturesAsync(planId, cancellationToken);
        });

    public Task<ServiceResult<AdminWriteResultDto>> SavePlanAsync(string? sessionToken, AdminPlanUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.PlansWrite, clientIp, cancellationToken);

            var name = request.Name.Trim();
            var code = request.Code.Trim();
            if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(code))
            {
                throw new ValidationException("Plan upsert called with a blank code or name.", "Give the plan a code and a name.");
            }
            request.Name = name;
            request.Code = code.ToUpperInvariant();

            var mutation = await contentProvider.UpsertPlanAsync(request, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, $"Plan '{name}' saved.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeletePlanAsync(string? sessionToken, Guid planId, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.PlansWrite, clientIp, cancellationToken);

            var mutation = await contentProvider.DeletePlanAsync(planId, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Plan deleted.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> SavePlanFeatureAsync(string? sessionToken, AdminPlanFeatureUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.PlansWrite, clientIp, cancellationToken);

            var text = request.FeatureText.Trim();
            if (string.IsNullOrWhiteSpace(text))
            {
                throw new ValidationException("Plan feature upsert called with blank text.", "Feature text can't be empty.");
            }
            request.FeatureText = text;

            var mutation = await contentProvider.UpsertPlanFeatureAsync(request, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Feature saved.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeletePlanFeatureAsync(string? sessionToken, Guid planFeatureId, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.PlansWrite, clientIp, cancellationToken);

            var mutation = await contentProvider.DeletePlanFeatureAsync(planFeatureId, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Feature removed.");
        });

    public Task<ServiceResult<AdminPlanEntitlementsModel?>> GetPlanEntitlementsAsync(string? sessionToken, Guid planId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await RequireAsync(sessionToken, AdminPermissions.PlansRead, null, cancellationToken);
            return await contentProvider.GetPlanEntitlementsAsync(planId, cancellationToken);
        });

    public Task<ServiceResult<AdminWriteResultDto>> SavePlanEntitlementsAsync(string? sessionToken, AdminPlanEntitlementsUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.PlansWrite, clientIp, cancellationToken);

            if (request.MaxActiveSplits is < 0 || request.MaxActiveDietPlans is < 0)
            {
                throw new ValidationException(
                    $"Plan entitlements upsert called with a negative limit (splits={request.MaxActiveSplits}, dietPlans={request.MaxActiveDietPlans}).",
                    "Limits can't be negative. Leave a field blank for unlimited.");
            }

            var mutation = await contentProvider.UpsertPlanEntitlementsAsync(request, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Entitlements saved.");
        });

    /* -------------------------------- splits -------------------------------- */

    public Task<ServiceResult<List<AdminSplitModel>>> GetSplitsAsync(string? sessionToken, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (actor, canManageAll) = await RequireSplitAsync(sessionToken, AdminPermissions.SplitsRead, null, cancellationToken);

            var splits = await contentProvider.GetSplitsAsync(actor.AdminUserId, canManageAll, cancellationToken);
            ApplySplitManageability(splits, actor, canManageAll);
            return splits;
        });

    public Task<ServiceResult<AdminSplitDetailModel>> GetSplitDetailAsync(string? sessionToken, Guid splitId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (actor, canManageAll) = await RequireSplitAsync(sessionToken, AdminPermissions.SplitsRead, null, cancellationToken);

            var detail = await contentProvider.GetSplitDetailAsync(splitId, actor.AdminUserId, canManageAll, cancellationToken)
                ?? throw new NotFoundException($"No split with id {splitId}.", "That split no longer exists.");

            ApplySplitManageability([detail.Split], actor, canManageAll);
            return detail;
        });

    public Task<ServiceResult<AdminWriteResultDto>> SaveSplitAsync(string? sessionToken, AdminSplitUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (actor, canManageAll) = await RequireSplitAsync(sessionToken, AdminPermissions.SplitsWrite, clientIp, cancellationToken);

            var name = request.Name.Trim();
            if (string.IsNullOrWhiteSpace(name))
            {
                throw new ValidationException("Split upsert called with a blank name.", "Give the split a name.");
            }
            AdminContentFieldRules.ThrowIfUnknown(request.Category, AdminContentFieldRules.SplitCategories, "category");
            AdminContentFieldRules.ThrowIfUnknown(request.Level, AdminContentFieldRules.SplitLevels, "level");
            AdminContentFieldRules.ThrowIfUnknownWhenSet(request.RecommendedGoal, AdminContentFieldRules.RecommendedGoals, "recommended goal");
            if (request.DurationDays is < 1 or > 14)
            {
                throw new ValidationException($"Split upsert called with out-of-range duration {request.DurationDays}.", "Duration must be between 1 and 14 days.");
            }

            // A trainer defaults to Private work unless they deliberately publish it;
            // an omitted value would otherwise be the property initializer's Public.
            request.Visibility = string.IsNullOrWhiteSpace(request.Visibility) ? "Private" : request.Visibility.Trim();
            AdminContentFieldRules.ThrowIfUnknown(request.Visibility, AdminContentFieldRules.SplitVisibilities, "visibility");
            request.Name = name;

            var mutation = await contentProvider.UpsertSplitAsync(request, actor, canManageAll, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, $"Split '{name}' saved.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteSplitAsync(string? sessionToken, Guid splitId, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (actor, canManageAll) = await RequireSplitAsync(sessionToken, AdminPermissions.SplitsWrite, clientIp, cancellationToken);

            var mutation = await contentProvider.DeleteSplitAsync(splitId, actor, canManageAll, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Split deleted.");
        });

    public Task<ServiceResult<List<AdminSplitAssignmentModel>>> GetSplitAssignmentsAsync(string? sessionToken, Guid splitId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            // Reading assignments only needs the split library read permission; the
            // ownership check matters on the mutations, not on who is assigned.
            await RequireAsync(sessionToken, AdminPermissions.SplitsRead, null, cancellationToken);
            return await contentProvider.GetSplitAssignmentsAsync(splitId, cancellationToken);
        });

    public Task<ServiceResult<AdminWriteResultDto>> AssignSplitAsync(string? sessionToken, AdminSplitAssignRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (actor, canManageAll) = await RequireSplitAsync(sessionToken, AdminPermissions.SplitsAssign, clientIp, cancellationToken);

            if (request.SplitId == Guid.Empty || request.UserId == Guid.Empty)
            {
                throw new ValidationException("Split assignment called without a split and a user.", "Choose a split and a client first.");
            }

            var mutation = await contentProvider.AssignSplitAsync(request, actor, canManageAll, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Split assigned.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> RemoveSplitAssignmentAsync(string? sessionToken, Guid splitId, Guid userId, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (actor, canManageAll) = await RequireSplitAsync(sessionToken, AdminPermissions.SplitsAssign, clientIp, cancellationToken);

            var mutation = await contentProvider.RemoveSplitAssignmentAsync(splitId, userId, actor, canManageAll, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Assignment removed.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> SaveSplitDayAsync(string? sessionToken, AdminSplitDayUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.SplitsWrite, clientIp, cancellationToken);

            var title = request.Title.Trim();
            if (string.IsNullOrWhiteSpace(title) && !request.IsRestDay)
            {
                throw new ValidationException("Split day upsert called with a blank title on a training day.", "Give the day a title.");
            }
            if (request.DayIndex < 1)
            {
                throw new ValidationException($"Split day upsert called with out-of-range day index {request.DayIndex}.", "Day index must be 1 or greater.");
            }
            request.Title = title;

            var mutation = await contentProvider.UpsertSplitDayAsync(request, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, $"Day {request.DayIndex} saved.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteSplitDayAsync(string? sessionToken, Guid splitDayId, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.SplitsWrite, clientIp, cancellationToken);

            var mutation = await contentProvider.DeleteSplitDayAsync(splitDayId, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Day removed.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> SaveSplitDayExerciseAsync(string? sessionToken, AdminSplitDayExerciseUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.SplitsWrite, clientIp, cancellationToken);

            if (request.TargetSets < 1)
            {
                throw new ValidationException($"Split day exercise upsert called with {request.TargetSets} target sets.", "Target sets must be at least 1.");
            }
            if (request.TargetRepsLow < 1 || request.TargetRepsHigh < request.TargetRepsLow)
            {
                throw new ValidationException(
                    $"Split day exercise upsert called with rep range {request.TargetRepsLow}-{request.TargetRepsHigh}.",
                    "The rep range must start at 1 or higher and the high end must not be below the low end.");
            }

            var mutation = await contentProvider.UpsertSplitDayExerciseAsync(request, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Exercise saved to the day.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteSplitDayExerciseAsync(string? sessionToken, Guid splitDayExerciseId, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.SplitsWrite, clientIp, cancellationToken);

            var mutation = await contentProvider.DeleteSplitDayExerciseAsync(splitDayExerciseId, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Exercise removed from the day.");
        });

    /* ------------------------------- diet plans ------------------------------ */

    public Task<ServiceResult<List<AdminDietPlanModel>>> GetDietPlansAsync(string? sessionToken, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (actor, canManageAll) = await RequireDietPlanAsync(sessionToken, AdminPermissions.DietPlansRead, null, cancellationToken);

            var plans = await contentProvider.GetDietPlansAsync(actor.AdminUserId, canManageAll, cancellationToken);
            ApplyDietPlanManageability(plans, actor, canManageAll);
            return plans;
        });

    public Task<ServiceResult<AdminDietPlanDetailModel>> GetDietPlanDetailAsync(string? sessionToken, Guid dietPlanId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (actor, canManageAll) = await RequireDietPlanAsync(sessionToken, AdminPermissions.DietPlansRead, null, cancellationToken);

            var detail = await contentProvider.GetDietPlanDetailAsync(dietPlanId, actor.AdminUserId, canManageAll, cancellationToken)
                ?? throw new NotFoundException($"No diet plan with id {dietPlanId}.", "That diet plan no longer exists.");

            ApplyDietPlanManageability([detail.Plan], actor, canManageAll);
            return detail;
        });

    public Task<ServiceResult<AdminWriteResultDto>> SaveDietPlanAsync(string? sessionToken, AdminDietPlanUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (actor, canManageAll) = await RequireDietPlanAsync(sessionToken, AdminPermissions.DietPlansWrite, clientIp, cancellationToken);

            var name = request.Name.Trim();
            if (string.IsNullOrWhiteSpace(name))
            {
                throw new ValidationException("Diet plan upsert called with a blank name.", "Give the plan a name.");
            }
            AdminContentFieldRules.ThrowIfUnknown(request.PeriodType, AdminContentFieldRules.DietPlanPeriodTypes, "period type");
            if (request.DurationDays is < 1 or > 31)
            {
                throw new ValidationException($"Diet plan upsert called with out-of-range duration {request.DurationDays}.", "Duration must be between 1 and 31 days.");
            }

            // A trainer defaults to Private work unless they deliberately publish it;
            // an omitted value would otherwise be the property initializer's Public.
            request.Visibility = string.IsNullOrWhiteSpace(request.Visibility) ? "Private" : request.Visibility.Trim();
            AdminContentFieldRules.ThrowIfUnknown(request.Visibility, AdminContentFieldRules.DietPlanVisibilities, "visibility");
            request.Name = name;

            var mutation = await contentProvider.UpsertDietPlanAsync(request, actor, canManageAll, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, $"Plan '{name}' saved.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteDietPlanAsync(string? sessionToken, Guid dietPlanId, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (actor, canManageAll) = await RequireDietPlanAsync(sessionToken, AdminPermissions.DietPlansWrite, clientIp, cancellationToken);

            var mutation = await contentProvider.DeleteDietPlanAsync(dietPlanId, actor, canManageAll, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Plan deleted.");
        });

    public Task<ServiceResult<List<AdminDietPlanAssignmentModel>>> GetDietPlanAssignmentsAsync(string? sessionToken, Guid dietPlanId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            // Reading assignments only needs the diet-plan library read permission; the
            // ownership check matters on the mutations, not on who is assigned.
            await RequireAsync(sessionToken, AdminPermissions.DietPlansRead, null, cancellationToken);
            return await contentProvider.GetDietPlanAssignmentsAsync(dietPlanId, cancellationToken);
        });

    public Task<ServiceResult<AdminWriteResultDto>> AssignDietPlanAsync(string? sessionToken, AdminDietPlanAssignRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (actor, canManageAll) = await RequireDietPlanAsync(sessionToken, AdminPermissions.DietPlansAssign, clientIp, cancellationToken);

            if (request.DietPlanId == Guid.Empty || request.UserId == Guid.Empty)
            {
                throw new ValidationException("Diet plan assignment called without a plan and a user.", "Choose a plan and a client first.");
            }

            var mutation = await contentProvider.AssignDietPlanAsync(request, actor, canManageAll, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Plan assigned.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> RemoveDietPlanAssignmentAsync(string? sessionToken, Guid dietPlanId, Guid userId, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (actor, canManageAll) = await RequireDietPlanAsync(sessionToken, AdminPermissions.DietPlansAssign, clientIp, cancellationToken);

            var mutation = await contentProvider.RemoveDietPlanAssignmentAsync(dietPlanId, userId, actor, canManageAll, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Assignment removed.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> SaveDietPlanDayAsync(string? sessionToken, AdminDietPlanDayUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.DietPlansWrite, clientIp, cancellationToken);

            if (request.DayIndex < 1)
            {
                throw new ValidationException($"Diet plan day upsert called with out-of-range day index {request.DayIndex}.", "Day index must be 1 or greater.");
            }
            request.Title = request.Title?.Trim();

            var mutation = await contentProvider.UpsertDietPlanDayAsync(request, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, $"Day {request.DayIndex} saved.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteDietPlanDayAsync(string? sessionToken, Guid dietPlanDayId, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.DietPlansWrite, clientIp, cancellationToken);

            var mutation = await contentProvider.DeleteDietPlanDayAsync(dietPlanDayId, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Day removed.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> SaveDietPlanMealAsync(string? sessionToken, AdminDietPlanMealUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.DietPlansWrite, clientIp, cancellationToken);

            AdminContentFieldRules.ThrowIfUnknown(request.MealType, AdminContentFieldRules.MealTypes, "meal type");
            if (request.MealSuggestionId == Guid.Empty)
            {
                throw new ValidationException("Diet plan meal upsert called without a meal suggestion.", "Choose a meal first.");
            }

            var mutation = await contentProvider.UpsertDietPlanMealAsync(request, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Meal saved to the day.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteDietPlanMealAsync(string? sessionToken, Guid dietPlanMealId, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.DietPlansWrite, clientIp, cancellationToken);

            var mutation = await contentProvider.DeleteDietPlanMealAsync(dietPlanMealId, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Meal removed from the day.");
        });

    /* --------------------------------- users -------------------------------- */

    public Task<ServiceResult<List<AdminUserSummaryModel>>> GetUsersAsync(string? sessionToken, string? search, int limit, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await RequireAsync(sessionToken, AdminPermissions.UsersRead, null, cancellationToken);
            return await contentProvider.GetUsersAsync(search, limit <= 0 ? 200 : limit, cancellationToken);
        });

    public Task<ServiceResult<AdminClientOverviewModel>> GetClientOverviewAsync(
        string? sessionToken, Guid userId, int days, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (userId == Guid.Empty)
            {
                throw new ValidationException("Client overview requested without a user.", "Choose a user first.");
            }

            // RequireWithPermissionsAsync, not RequireAsync: whether the operator may
            // open someone who is not their client depends on a second permission.
            var (actor, permissions) = await AdminPermissionGuard.RequireWithPermissionsAsync(
                adminProvider, adminRbacProvider, sessionToken, AdminPermissions.UsersDataRead, null, cancellationToken);

            if (!permissions.Contains(AdminPermissions.UsersDataReadAll)
                && !await contentProvider.IsClientAssignedToAsync(actor.AdminUserId ?? Guid.Empty, userId, cancellationToken))
            {
                throw new ForbiddenException(
                    $"Operator {LogRedaction.Tag(actor.Username)} called the client overview for a user who is not " +
                    $"their client and lacks '{AdminPermissions.UsersDataReadAll}'.");
            }

            var toDate = DateTime.UtcNow.Date;
            var fromDate = toDate.AddDays(-Math.Clamp(days, 1, 365) + 1);

            return await contentProvider.GetClientOverviewAsync(userId, fromDate, toDate, cancellationToken)
                ?? throw new NotFoundException(
                    $"Client overview requested for unknown user {userId}.", "That user no longer exists.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> SeedUserMockDataAsync(
        string? sessionToken,
        AdminMockDataRequest request,
        string? clientIp,
        CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.UsersMockData, clientIp, cancellationToken);

            if (request.UserId == Guid.Empty)
            {
                throw new ValidationException("Mock-data seed called without a user.", "Choose a user first.");
            }

            var profile = string.IsNullOrWhiteSpace(request.Profile) ? MockDataProfiles.Advanced : request.Profile.Trim();
            if (!MockDataProfiles.All.Contains(profile, StringComparer.Ordinal))
            {
                throw new ValidationException(
                    $"Mock-data seed called with unknown profile '{profile}'.",
                    "Choose a valid mock-data profile.");
            }

            var days = request.Days <= 0 ? 30 : Math.Min(request.Days, 365);

            var result = await mockDataSeeder.SeedUserAsync(request.UserId, profile, days, request.Seed, actor, cancellationToken)
                ?? throw new NotFoundException($"Mock-data seed called for unknown user {request.UserId}.", "That user no longer exists.");

            return new AdminWriteResultDto
            {
                Id = result.UserId,
                Message = $"Generated {result.Days} day(s) of {result.Profile} mock data: " +
                          $"{result.WorkoutsCompleted} workouts, {result.MealsLogged} meals logged."
            };
        });

    private Task<AdminActorModel> RequireAsync(string? sessionToken, string permission, string? clientIp, CancellationToken cancellationToken) =>
        AdminPermissionGuard.RequireAsync(adminProvider, adminRbacProvider, sessionToken, permission, clientIp, cancellationToken);

    /// <summary>Passes when the operator holds any one of the supplied permissions. Used by
    /// the content-library reads that other editors depend on - see
    /// <see cref="AdminPermissionGuard.RequireAnyAsync"/>.</summary>
    private async Task<AdminActorModel> RequireAnyAsync(
        string? sessionToken, IReadOnlyCollection<string> permissions, CancellationToken cancellationToken)
    {
        var (actor, _) = await AdminPermissionGuard.RequireAnyAsync(
            adminProvider, adminRbacProvider, sessionToken, permissions, null, cancellationToken);

        return actor;
    }

    /// <summary>
    /// Split endpoints need one permission *and* to know whether the operator holds
    /// content.splits.manage_all, which decides if they may touch a split they don't
    /// own. One session lookup answers both.
    /// </summary>
    private async Task<(AdminActorModel Actor, bool CanManageAll)> RequireSplitAsync(
        string? sessionToken, string permission, string? clientIp, CancellationToken cancellationToken)
    {
        var (actor, permissions) = await AdminPermissionGuard.RequireWithPermissionsAsync(
            adminProvider, adminRbacProvider, sessionToken, permission, clientIp, cancellationToken);

        return (actor, permissions.Contains(AdminPermissions.SplitsManageAll));
    }

    /// <summary>Marks each split with whether this operator may edit/delete/assign it,
    /// so the console can hide the controls instead of letting a click eat a 409.</summary>
    private static void ApplySplitManageability(List<AdminSplitModel> splits, AdminActorModel actor, bool canManageAll)
    {
        foreach (var split in splits)
        {
            split.CanManage = canManageAll
                || (actor.AdminUserId is { } actorId && split.OwnerAdminUserId == actorId);
        }
    }

    /// <summary>Diet-plan endpoints need one permission *and* to know whether the operator holds
    /// content.diet_plans.manage_all, which decides if they may touch a plan they don't own.
    /// One session lookup answers both.</summary>
    private async Task<(AdminActorModel Actor, bool CanManageAll)> RequireDietPlanAsync(
        string? sessionToken, string permission, string? clientIp, CancellationToken cancellationToken)
    {
        var (actor, permissions) = await AdminPermissionGuard.RequireWithPermissionsAsync(
            adminProvider, adminRbacProvider, sessionToken, permission, clientIp, cancellationToken);

        return (actor, permissions.Contains(AdminPermissions.DietPlansManageAll));
    }

    /// <summary>Marks each plan with whether this operator may edit/delete/assign it,
    /// so the console can hide the controls instead of letting a click eat a 409.</summary>
    private static void ApplyDietPlanManageability(List<AdminDietPlanModel> plans, AdminActorModel actor, bool canManageAll)
    {
        foreach (var plan in plans)
        {
            plan.CanManage = canManageAll
                || (actor.AdminUserId is { } actorId && plan.OwnerAdminUserId == actorId);
        }
    }
}
