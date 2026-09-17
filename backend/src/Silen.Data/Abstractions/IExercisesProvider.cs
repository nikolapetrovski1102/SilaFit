using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IExercisesProvider
{
    /// <summary>Exercises matching an optional search text and an optional set of
    /// coarse muscle groups. An empty/null <paramref name="muscleGroups"/> means
    /// "any group" rather than "no groups".</summary>
    Task<List<ExerciseModel>> SearchAsync(IReadOnlyList<string>? muscleGroups, string? searchText, CancellationToken cancellationToken = default);
}
