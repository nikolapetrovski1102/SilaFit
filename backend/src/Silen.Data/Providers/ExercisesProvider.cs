using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class ExercisesProvider(ISqlExecutor sqlExecutor) : IExercisesProvider
{
    public Task<List<ExerciseModel>> SearchAsync(string? muscleGroup, string? searchText, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Exercises_Search",
            [SqlParameterBuilder.Create("@MuscleGroup", muscleGroup), SqlParameterBuilder.Create("@SearchText", searchText)],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapExercise, cancellationToken),
            cancellationToken);
}
