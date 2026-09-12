using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="ISplitService"/>
public sealed class SplitService(ISplitsProvider splitsProvider, IUserProfileProvider userProfileProvider) : ISplitService
{
    public Task<ServiceResult<List<WorkoutSplitModel>>> GetAllAsync(Guid? userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var splits = await splitsProvider.GetAllAsync(cancellationToken);

            // Profile lookup is best-effort: a guest/registered user who hasn't
            // finished onboarding yet simply gets no recommendation, not an error.
            var goal = userId is { } id
                ? (await userProfileProvider.GetAsync(id, cancellationToken))?.Goal
                : null;

            if (goal is not null)
            {
                foreach (var split in splits)
                {
                    split.MatchesGoal = split.RecommendedGoal == goal;
                }
            }

            return splits;
        });

    public Task<ServiceResult<SplitDetailDto>> GetDetailAsync(Guid splitId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (split, days, exercises) = await splitsProvider.GetDetailAsync(splitId, cancellationToken);

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
            await splitsProvider.SetActiveAsync(userId, request.SplitId, cancellationToken)
                ?? throw new NotFoundException($"Split '{request.SplitId}' could not be activated for user '{userId}'.", "That split couldn't be activated."));
}
