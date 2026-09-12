using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IExercisesProvider
{
    Task<List<ExerciseModel>> SearchAsync(string? muscleGroup, string? searchText, CancellationToken cancellationToken = default);
}
