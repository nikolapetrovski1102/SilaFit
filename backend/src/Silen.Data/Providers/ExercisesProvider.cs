using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class ExercisesProvider(ISqlExecutor sqlExecutor) : IExercisesProvider
{
    public Task<List<ExerciseModel>> SearchAsync(IReadOnlyList<string>? muscleGroups, string? searchText, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Exercises_Search",
            [SqlParameterBuilder.Create("@MuscleGroups", ToCsv(muscleGroups)), SqlParameterBuilder.Create("@SearchText", searchText)],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapExercise, cancellationToken),
            cancellationToken);

    /// <summary>Collapses the requested groups into the comma-separated value the
    /// proc expects, dropping blanks/duplicates so an empty selection becomes a
    /// NULL ("any group") filter instead of a match-nothing list.</summary>
    private static string? ToCsv(IReadOnlyList<string>? muscleGroups) =>
        muscleGroups is { Count: > 0 }
            ? string.Join(',', muscleGroups
                .Where(group => !string.IsNullOrWhiteSpace(group))
                .Select(group => group.Trim().ToLowerInvariant())
                .Distinct())
            : null;
}
