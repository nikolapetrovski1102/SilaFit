using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

/// <summary>
/// Weekly batch that, for every active Advanced subscriber, looks at what they
/// actually trained and ate last week and generates a brand-new custom split and
/// diet plan for the upcoming week - the weekly, content-generating counterpart
/// of <see cref="IMonthlyReviewService"/>. The model may decide the current
/// split already fits and recommend keeping it; the diet plan always covers the
/// full week (Monday-Sunday, breakfast/lunch/dinner plus target-filling snacks) and carries a
/// week-long shopping list aggregated from the meals' ingredients. Generated
/// diet plans become active automatically for Advanced subscribers.
/// Designed to run every Sunday and be safely re-runnable: a user already settled for
/// a given week (see <c>IWeeklyPlanGenerationProvider.GetProcessedUserIdsAsync</c>) is
/// skipped on a later run for that same week.
/// </summary>
public interface IWeeklyPlanGenerationService
{
    /// <param name="weekStartUtc">The Monday of the week to generate a plan for. When null,
    /// the ISO week containing the current UTC date is used - the natural period for a job
    /// that runs on the Sunday that week ends.</param>
    /// <param name="dryRun">Runs the full gating/evidence/AI pipeline but writes nothing:
    /// no split/diet-plan rows, no activation, no notification, no run/delivery bookkeeping.</param>
    /// <param name="onlyUserId">Restricts the run to a single candidate, for manual testing.</param>
    Task<ServiceResult<WeeklyPlanGenerationSummaryDto>> RunAsync(
        DateTime? weekStartUtc, bool dryRun, Guid? onlyUserId, CancellationToken cancellationToken = default);

    /// <summary>Builds one fresh weekly diet plan for a single user, on demand, from the
    /// calorie/macro targets and recent logged-meal evidence - the same pipeline the
    /// weekly batch runs, but immediate and always activated. Backs the Nutrition
    /// screen's "Generate plan" action.</summary>
    Task<ServiceResult<DietPlanDetailDto>> GenerateDietPlanForUserAsync(
        Guid userId, CancellationToken cancellationToken = default);
}
