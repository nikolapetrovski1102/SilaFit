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
public sealed class DietPlanService(
    IDietPlansProvider dietPlansProvider, ISubscriptionGate subscriptionGate, IMealPlanningService mealPlanningService) : IDietPlanService
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
            var (plan, days, meals, ingredients) = await dietPlansProvider.GetDetailAsync(dietPlanId, userId, cancellationToken);

            if (plan is null)
            {
                throw new NotFoundException($"Diet plan '{dietPlanId}' was not found.", "That diet plan couldn't be found.");
            }

            if (userId is { } callerId)
            {
                plan.IsEditableByMe = plan.OwnerUserId == callerId;
            }

            return BuildDetail(plan, days, meals, ingredients);
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

            var (plan, days, meals, ingredients) = await dietPlansProvider.GetDetailAsync(active.DietPlanId, userId, cancellationToken);
            if (plan is null)
            {
                return null;
            }

            plan.IsEditableByMe = plan.OwnerUserId == userId;
            return BuildDetail(plan, days, meals, ingredients);
        });

    public Task<ServiceResult<AdminWriteResultDto>> ActivateAsync(Guid userId, Guid dietPlanId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            // Reuse the detail read as the visibility check: a private/shared plan
            // the caller can't see comes back null, so it can't be activated. The
            // same read also gives us the days/meals needed to fill the week below,
            // so activating never re-fetches them a second time.
            var (plan, days, meals, _) = await dietPlansProvider.GetDetailAsync(dietPlanId, userId, cancellationToken);
            if (plan is null)
            {
                throw new NotFoundException($"Diet plan '{dietPlanId}' was not found.", "That diet plan couldn't be found.");
            }

            await dietPlansProvider.SetActiveDietPlanAsync(userId, dietPlanId, cancellationToken);
            await ApplyToUpcomingWeekCoreAsync(userId, plan, days, meals, cancellationToken);

            return new AdminWriteResultDto
            {
                Id = dietPlanId,
                Message = $"'{plan.Name}' is now your active plan."
            };
        });

    public Task<ServiceResult<int>> ApplyToUpcomingWeekAsync(Guid userId, Guid dietPlanId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (plan, days, meals, _) = await dietPlansProvider.GetDetailAsync(dietPlanId, userId, cancellationToken);
            if (plan is null)
            {
                throw new NotFoundException($"Diet plan '{dietPlanId}' was not found.", "That diet plan couldn't be found.");
            }

            return await ApplyToUpcomingWeekCoreAsync(userId, plan, days, meals, cancellationToken);
        });

    /// <summary>Maps each of the next 7 calendar days (starting today, UTC) onto
    /// <paramref name="plan"/>'s day cycle and bulk-applies that day's meals as
    /// Planned meal logs. Mirrors `_PlanDayCard._dayIndexFor` in the Flutter app
    /// exactly (Mon=1..Sun=7 for a 7-day plan; a day-of-year rotation for any other
    /// length), so the meals applied here are the same ones the Active Diet Plan
    /// card would already show for that day.</summary>
    private async Task<int> ApplyToUpcomingWeekCoreAsync(
        Guid userId, DietPlanModel plan, List<DietPlanDayModel> days, List<DietPlanMealModel> meals, CancellationToken cancellationToken)
    {
        if (days.Count == 0)
        {
            return 0;
        }

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var requests = new List<UpsertMealLogRequest>();
        for (var offset = 0; offset < 7; offset++)
        {
            var date = today.AddDays(offset);
            var dayIndex = DayIndexFor(date, plan.DurationDays);
            var planDay = days.FirstOrDefault(d => d.DayIndex == dayIndex) ?? days[0];

            requests.AddRange(meals
                .Where(m => m.DietPlanDayId == planDay.DietPlanDayId)
                .Select(meal => new UpsertMealLogRequest
                {
                    LogDateUtc = date,
                    MealType = meal.MealType,
                    Title = meal.Title,
                    CaloriesKcal = meal.CaloriesKcal,
                    ProteinG = meal.ProteinG,
                    CarbsG = meal.CarbsG,
                    FatsG = meal.FatsG,
                    Status = "Planned"
                }));
        }

        if (requests.Count == 0)
        {
            return 0;
        }

        return RequireData(
            await mealPlanningService.ApplyPlannedMealsAsync(userId, requests, cancellationToken),
            "Apply diet plan to upcoming week");
    }

    private static int DayIndexFor(DateOnly date, int durationDays)
    {
        var days = durationDays <= 0 ? 1 : durationDays;
        if (days == 7)
        {
            return date.DayOfWeek == DayOfWeek.Sunday ? 7 : (int)date.DayOfWeek;
        }

        var dayOfYear = date.DayOfYear;
        return ((dayOfYear - 1) % days) + 1;
    }

    private static T RequireData<T>(ServiceResult<T> result, string action)
    {
        if (!result.IsSuccess)
        {
            throw new InvalidOperationException($"{action} failed: {result.LogMessage ?? result.UserMessage ?? "unknown error"}.");
        }

        return result.Data!;
    }

    private static DietPlanDetailDto BuildDetail(
        DietPlanModel plan, List<DietPlanDayModel> days, List<DietPlanMealModel> meals, List<string> ingredients)
    {
        // Combine compatible quantities across the week's meals: three "2
        // eggs" rows become one "Eggs ×6" line rather than "2 eggs ×3".
        var shoppingList = IngredientSummaryFormatter.Summarize(ingredients);

        return new DietPlanDetailDto
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
                .ToList(),
            ShoppingList = shoppingList
        };
    }

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
