using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="ISplitService"/>
public sealed class SplitService(ISplitsProvider splitsProvider, IUserProfileProvider userProfileProvider) : ISplitService
{
    public Task<ServiceResult<List<WorkoutSplitModel>>> GetAllAsync(Guid? userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var splits = await splitsProvider.GetAllAsync(userId, cancellationToken);

            // Profile lookup is best-effort: a guest/registered user who hasn't
            // finished onboarding yet simply gets the curated default ordering.
            var profile = userId is { } id
                ? await userProfileProvider.GetAsync(id, cancellationToken)
                : null;

            var goal = profile?.Goal;
            if (goal is not null)
            {
                foreach (var split in splits)
                {
                    split.MatchesGoal = split.RecommendedGoal == goal;
                }
            }

            // Person-fit (goal + age/BMI level fit + category affinity) is
            // computed server-side so both the screens and the account-creation
            // auto-assign agree on the same best pick; the list comes back
            // best-first so the client's hero is simply the first row.
            return SplitRecommendationScorer.Rank(splits, PersonFit.From(profile), goal);
        });

    public Task<ServiceResult<SplitDetailDto>> GetDetailAsync(Guid splitId, Guid? userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (split, days, exercises) = await splitsProvider.GetDetailAsync(splitId, userId, cancellationToken);

            if (split is null)
            {
                throw new NotFoundException($"Split '{splitId}' was not found.", "That split couldn't be found.");
            }

            return new SplitDetailDto
            {
                Split = split,
                Days = days
                    .OrderBy(d => d.DayIndex)
                    .Select(day => new SplitDayWithExercisesDto
                    {
                        Day = day,
                        Exercises = exercises
                            .Where(e => e.SplitDayId == day.SplitDayId)
                            .OrderBy(e => e.SortOrder)
                            .ToList()
                    })
                    .ToList()
            };
        });

    public Task<ServiceResult<ActiveSplitModel>> ActivateAsync(Guid userId, ActivateSplitRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
            await splitsProvider.SetActiveAsync(userId, request.SplitId, isAutoAssigned: false, cancellationToken: cancellationToken)
                ?? throw new NotFoundException($"Split '{request.SplitId}' could not be activated for user '{userId}'.", "That split couldn't be activated."));

    public Task<ServiceResult<ActiveSplitModel?>> AutoAssignRecommendedAsync(Guid userId, UserProfileModel profile, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var active = await splitsProvider.GetActiveAsync(userId, cancellationToken);

            // Never override a split the user picked for themselves via the
            // Splits screen - only a split still flagged as the recommender's
            // own pick (IsAutoAssigned) is ever eligible for a re-check, so
            // this stays a one-time default for anyone who has made their own
            // choice, while still tracking later onboarding answers for
            // anyone who hasn't.
            if (active is not null && !active.IsAutoAssigned)
            {
                return (ActiveSplitModel?)null;
            }

            if (profile.Goal is null)
            {
                return null;
            }

            var splits = await splitsProvider.GetAllAsync(userId, cancellationToken);

            // Same scorer the Splits screen uses, so the split auto-selected at
            // account creation - or re-checked after later onboarding answers -
            // is exactly the one that would be shown as "best for you" - no
            // second, divergent notion of "recommended". The pick honors the
            // person's weekly schedule: a split that needs more days than they
            // answered can never be auto-activated while a compatible one exists,
            // and the closest cadence is used when none fits at all.
            var fit = PersonFit.From(profile);
            var ranked = SplitRecommendationScorer.Rank(splits, fit, profile.Goal);
            var recommended = SplitRecommendationScorer.PickForAutoAssign(ranked, fit);

            if (recommended is null)
            {
                return null;
            }

            // Already on the current best pick - skip the write so a profile
            // save that didn't change any capacity answer doesn't needlessly
            // bump ActivatedAtUtc.
            if (active is not null && active.SplitId == recommended.SplitId)
            {
                return null;
            }

            return await splitsProvider.SetActiveAsync(userId, recommended.SplitId, isAutoAssigned: true, cancellationToken: cancellationToken);
        });
}
