using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>App-facing exercise search - backs both the split builder's exercise
/// picker and the live-workout swap/add sheet.</summary>
public interface IExercisesService
{
    /// <summary>The catalogue plus <paramref name="userId"/>'s own exercises.</summary>
    Task<ServiceResult<List<ExerciseModel>>> SearchAsync(
        Guid? userId, string? muscleGroup, string? searchText, CancellationToken cancellationToken = default);

    /// <summary>Exercises ranked for this caller's equipment and experience, best
    /// first, with MatchScore/MatchReason stamped on each. Used to seed the
    /// custom-split builder with sensible picks instead of a blank list.
    /// <paramref name="muscleGroups"/> scopes and prioritises the list to the
    /// groups a day's title (and/or the exercises already on it) points at;
    /// null/empty keeps the generic best-for-you ranking.</summary>
    Task<ServiceResult<List<ExerciseModel>>> SuggestAsync(
        Guid? userId, IReadOnlyList<string>? muscleGroups, int limit, CancellationToken cancellationToken = default);

    /// <summary>"Did you mean" picks for a search that found nothing - names a
    /// typo or two away from what was typed. Empty when nothing is close, which
    /// is the picker's cue to offer adding the exercise.</summary>
    Task<ServiceResult<List<ExerciseModel>>> CloseMatchesAsync(
        Guid userId, string? searchText, CancellationToken cancellationToken = default);

    /// <summary>Adds an exercise the catalogue is missing, private to
    /// <paramref name="userId"/>. Returns the existing row instead when the
    /// catalogue or the user already has that name.</summary>
    Task<ServiceResult<ExerciseModel>> CreateCustomAsync(
        Guid userId, CreateCustomExerciseRequest request, CancellationToken cancellationToken = default);
}
