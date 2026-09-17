using Silen.Common.Contracts;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>App-facing exercise search - backs both the split builder's exercise
/// picker and the live-workout swap/add sheet.</summary>
public interface IExercisesService
{
    Task<ServiceResult<List<ExerciseModel>>> SearchAsync(string? muscleGroup, string? searchText, CancellationToken cancellationToken = default);

    /// <summary>Exercises ranked for this caller's equipment and experience, best
    /// first, with MatchScore/MatchReason stamped on each. Used to seed the
    /// custom-split builder with sensible picks instead of a blank list.
    /// <paramref name="muscleGroups"/> scopes and prioritises the list to the
    /// groups a day's title (and/or the exercises already on it) points at;
    /// null/empty keeps the generic best-for-you ranking.</summary>
    Task<ServiceResult<List<ExerciseModel>>> SuggestAsync(
        Guid? userId, IReadOnlyList<string>? muscleGroups, int limit, CancellationToken cancellationToken = default);
}
