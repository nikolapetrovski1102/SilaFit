using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IExercisesProvider
{
    /// <summary>Exercises matching an optional search text and an optional set of
    /// coarse muscle groups. An empty/null <paramref name="muscleGroups"/> means
    /// "any group" rather than "no groups". <paramref name="userId"/> adds that
    /// user's own exercises to the catalogue; null reads the catalogue alone.</summary>
    Task<List<ExerciseModel>> SearchAsync(
        IReadOnlyList<string>? muscleGroups, string? searchText, Guid? userId, CancellationToken cancellationToken = default);

    /// <summary>Every exercise <paramref name="userId"/> can pick - the catalogue
    /// plus their own - for the typo-tolerant "did you mean" pass.</summary>
    Task<List<ExerciseModel>> GetPickableAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Adds a private exercise for <paramref name="userId"/>, or returns
    /// the one they (or the catalogue) already have under the same name.</summary>
    Task<ExerciseModel> CreateCustomAsync(
        Guid userId, string name, string muscleGroup, string equipmentType, bool isCompound,
        CancellationToken cancellationToken = default);
}
