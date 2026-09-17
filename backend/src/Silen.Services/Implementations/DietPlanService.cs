using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IDietPlanService"/>
public sealed class DietPlanService(IDietPlansProvider dietPlansProvider, ISubscriptionGate subscriptionGate) : IDietPlanService
{
    public Task<ServiceResult<List<DietPlanModel>>> GetAllAsync(Guid? userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var plans = await dietPlansProvider.GetAllAsync(userId, cancellationToken);

            if (userId is { } callerId)
            {
                foreach (var plan in plans)
                {
                    plan.IsEditableByMe = plan.OwnerUserId == callerId;
                }
            }

            return plans;
        });

    public Task<ServiceResult<DietPlanDetailDto>> GetDetailAsync(Guid dietPlanId, Guid? userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (plan, days, meals) = await dietPlansProvider.GetDetailAsync(dietPlanId, userId, cancellationToken);

            if (plan is null)
            {
                throw new NotFoundException($"Diet plan '{dietPlanId}' was not found.", "That diet plan couldn't be found.");
            }

            if (userId is { } callerId)
            {
                plan.IsEditableByMe = plan.OwnerUserId == callerId;
            }

            return BuildDetail(plan, days, meals);
        });

    public Task<ServiceResult<DietPlanDetailDto?>> GetActiveAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync<DietPlanDetailDto?>(async () =>
        {
            var active = await dietPlansProvider.GetActiveAsync(userId, cancellationToken);

            // No active plan is a normal state (a new user hasn't picked one yet), not
            // an error - the Nutrition screen renders its "choose a plan" empty state.
            if (active is null)
            {
                return null;
            }

            var (plan, days, meals) = await dietPlansProvider.GetDetailAsync(active.DietPlanId, userId, cancellationToken);
            if (plan is null)
            {
                return null;
            }

            plan.IsEditableByMe = plan.OwnerUserId == userId;
            return BuildDetail(plan, days, meals);
        });

    public Task<ServiceResult<AdminWriteResultDto>> ActivateAsync(Guid userId, Guid dietPlanId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            // Reuse the detail read as the visibility check: a private/shared plan
            // the caller can't see comes back null, so it can't be activated.
            var (plan, _, _) = await dietPlansProvider.GetDetailAsync(dietPlanId, userId, cancellationToken);
            if (plan is null)
            {
                throw new NotFoundException($"Diet plan '{dietPlanId}' was not found.", "That diet plan couldn't be found.");
            }

            await dietPlansProvider.SetActiveDietPlanAsync(userId, dietPlanId, cancellationToken);
            return new AdminWriteResultDto
            {
                Id = dietPlanId,
                Message = $"'{plan.Name}' is now your active plan."
            };
        });

    private static DietPlanDetailDto BuildDetail(
        DietPlanModel plan, List<DietPlanDayModel> days, List<DietPlanMealModel> meals) =>
        new()
        {
            Plan = plan,
            Days = days
                .OrderBy(d => d.DayIndex)
                .Select(day => new DietPlanDayWithMealsDto
                {
                    Day = day,
                    Meals = meals
                        .Where(m => m.DietPlanDayId == day.DietPlanDayId)
                        .OrderBy(m => m.SortOrder)
                        .ToList()
                })
                .ToList()
        };

    /* ----------------------------- user-owned diet plans ----------------------------- */

    public Task<ServiceResult<List<DietPlanModel>>> GetMyPlansAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var plans = await dietPlansProvider.GetOwnedAsync(userId, cancellationToken);
            foreach (var plan in plans)
            {
                plan.IsEditableByMe = true;
            }
            return plans;
        });

    public Task<ServiceResult<AdminWriteResultDto>> CreateOrUpdateMyPlanAsync(Guid userId, UserDietPlanUpsertRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
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
            request.Name = name;

            if (request.DietPlanId is null)
            {
                var entitlements = await subscriptionGate.GetEntitlementsAsync(userId, cancellationToken);

                if (request.IsAiGenerated && !entitlements.AllowAiGeneration)
                {
                    throw new PlanLimitExceededException(
                        $"User '{userId}' requested an AI-generated diet plan without AllowAiGeneration.",
                        "AI-generated diet plans aren't included in your plan. Upgrade to unlock them.");
                }

                if (entitlements.MaxActiveDietPlans is { } maxPlans)
                {
                    var owned = await dietPlansProvider.GetOwnedAsync(userId, cancellationToken);
                    if (owned.Count >= maxPlans)
                    {
                        throw new PlanLimitExceededException(
                            $"User '{userId}' has {owned.Count} diet plans, at or above their plan's limit of {maxPlans}.",
                            "You've reached your plan's limit on saved diet plans. Upgrade to add more.");
                    }
                }
            }

            var mutation = await dietPlansProvider.UpsertUserDietPlanAsync(request, userId, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, $"Plan '{name}' saved.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> KeepMyPlanAsync(Guid userId, Guid dietPlanId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var mutation = await dietPlansProvider.KeepUserDietPlanAsync(dietPlanId, userId, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "This plan is now permanent.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteMyPlanAsync(Guid userId, Guid dietPlanId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var mutation = await dietPlansProvider.DeleteUserDietPlanAsync(dietPlanId, userId, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Plan deleted.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> SaveMyPlanDayAsync(Guid userId, UserDietPlanDayUpsertRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (request.DayIndex < 1)
            {
                throw new ValidationException($"Diet plan day upsert called with out-of-range day index {request.DayIndex}.", "Day index must be 1 or greater.");
            }
            request.Title = request.Title?.Trim();

            var mutation = await dietPlansProvider.UpsertUserDietPlanDayAsync(request, userId, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, $"Day {request.DayIndex} saved.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteMyPlanDayAsync(Guid userId, Guid dietPlanDayId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var mutation = await dietPlansProvider.DeleteUserDietPlanDayAsync(dietPlanDayId, userId, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Day removed.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> SaveMyPlanMealAsync(Guid userId, UserDietPlanMealUpsertRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            AdminContentFieldRules.ThrowIfUnknown(request.MealType, AdminContentFieldRules.MealTypes, "meal type");
            if (request.MealSuggestionId == Guid.Empty)
            {
                throw new ValidationException("Diet plan meal upsert called without a meal suggestion.", "Choose a meal first.");
            }

            var mutation = await dietPlansProvider.UpsertUserDietPlanMealAsync(request, userId, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Meal saved to the day.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteMyPlanMealAsync(Guid userId, Guid dietPlanMealId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var mutation = await dietPlansProvider.DeleteUserDietPlanMealAsync(dietPlanMealId, userId, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Meal removed from the day.");
        });
}
