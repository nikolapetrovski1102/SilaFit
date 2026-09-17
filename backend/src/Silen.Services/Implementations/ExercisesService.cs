using Silen.Common.Contracts;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IExercisesService"/>
public sealed class ExercisesService(
    IExercisesProvider exercisesProvider,
    IUserProfileProvider userProfileProvider) : IExercisesService
{
    public Task<ServiceResult<List<ExerciseModel>>> SearchAsync(string? muscleGroup, string? searchText, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(() => exercisesProvider.SearchAsync(
            string.IsNullOrWhiteSpace(muscleGroup)
                ? null
                : new[] { muscleGroup.Trim().ToLowerInvariant() },
            searchText,
            cancellationToken));

    public Task<ServiceResult<List<ExerciseModel>>> SuggestAsync(
        Guid? userId, IReadOnlyList<string>? muscleGroups, int limit, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            // The coarse groups already scope the query set; passing them on to the
            // scorer keeps the requested order when a day names several (e.g.
            // "Chest & Triceps" surfaces chest first, arms after) without letting
            // group intent override equipment/experience fitness.
            var exercises = await exercisesProvider.SearchAsync(muscleGroups, null, cancellationToken);

            // Profile lookup is best-effort, same as the split scorer: a guest or a
            // user who hasn't finished onboarding still gets a sensible list, just
            // without the equipment/experience personalisation.
            var profile = userId is { } id
                ? await userProfileProvider.GetAsync(id, cancellationToken)
                : null;

            return ExerciseRecommendationScorer.Rank(
                exercises, PersonFit.From(profile), Math.Clamp(limit, 1, 50), muscleGroups);
        });
}
