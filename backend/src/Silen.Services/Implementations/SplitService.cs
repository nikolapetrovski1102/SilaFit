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
public sealed class SplitService(ISplitsProvider splitsProvider, IUserProfileProvider userProfileProvider, ISubscriptionGate subscriptionGate) : ISplitService
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

            if (userId is { } callerId)
            {
                foreach (var split in splits)
                {
                    split.IsEditableByMe = split.OwnerUserId == callerId;
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

            if (userId is { } callerId)
            {
                split.IsEditableByMe = split.OwnerUserId == callerId;
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

    /* ----------------------------- user-owned splits ----------------------------- */

    public Task<ServiceResult<List<WorkoutSplitModel>>> GetMySplitsAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var splits = await splitsProvider.GetOwnedSplitsAsync(userId, cancellationToken);
            foreach (var split in splits)
            {
                split.IsEditableByMe = true;
            }
            return splits;
        });

    public Task<ServiceResult<AdminWriteResultDto>> CreateOrUpdateMySplitAsync(Guid userId, UserSplitUpsertRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
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
            request.Name = name;

            if (request.SplitId is null)
            {
                var entitlements = await subscriptionGate.GetEntitlementsAsync(userId, cancellationToken);

                if (request.IsAiGenerated && !entitlements.AllowAiGeneration)
                {
                    throw new PlanLimitExceededException(
                        $"User '{userId}' requested an AI-generated split without AllowAiGeneration.",
                        "AI-generated splits aren't included in your plan. Upgrade to unlock them.");
                }

                if (entitlements.MaxActiveSplits is { } maxSplits)
                {
                    var owned = await splitsProvider.GetOwnedSplitsAsync(userId, cancellationToken);
                    if (owned.Count >= maxSplits)
                    {
                        throw new PlanLimitExceededException(
                            $"User '{userId}' has {owned.Count} splits, at or above their plan's limit of {maxSplits}.",
                            "You've reached your plan's limit on saved splits. Upgrade to add more.");
                    }
                }
            }

            var mutation = await splitsProvider.UpsertUserSplitAsync(request, userId, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, $"Split '{name}' saved.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> KeepMySplitAsync(Guid userId, Guid splitId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var mutation = await splitsProvider.KeepUserSplitAsync(splitId, userId, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "This split is now permanent.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteMySplitAsync(Guid userId, Guid splitId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var mutation = await splitsProvider.DeleteUserSplitAsync(splitId, userId, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Split deleted.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> SaveMySplitDayAsync(Guid userId, UserSplitDayUpsertRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
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

            var mutation = await splitsProvider.UpsertUserSplitDayAsync(request, userId, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, $"Day {request.DayIndex} saved.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteMySplitDayAsync(Guid userId, Guid splitDayId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var mutation = await splitsProvider.DeleteUserSplitDayAsync(splitDayId, userId, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Day removed.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> SaveMySplitDayExerciseAsync(Guid userId, UserSplitDayExerciseUpsertRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
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

            var mutation = await splitsProvider.UpsertUserSplitDayExerciseAsync(request, userId, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Exercise saved to the day.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteMySplitDayExerciseAsync(Guid userId, Guid splitDayExerciseId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var mutation = await splitsProvider.DeleteUserSplitDayExerciseAsync(splitDayExerciseId, userId, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Exercise removed from the day.");
        });
}
