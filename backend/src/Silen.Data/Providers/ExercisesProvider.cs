using System.Text.Json;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class ExercisesProvider(ISqlExecutor sqlExecutor) : IExercisesProvider
{
    public Task<List<ExerciseModel>> SearchAsync(
        IReadOnlyList<string>? muscleGroups, string? searchText, Guid? userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Exercises_Search",
            [
                SqlParameterBuilder.Create("@MuscleGroups", ToCsv(muscleGroups)),
                SqlParameterBuilder.Create("@SearchText", searchText),
                SqlParameterBuilder.Create("@SearchTermsJson", ToTermsJson(searchText)),
                SqlParameterBuilder.Create("@UserId", userId)
            ],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapExercise, cancellationToken),
            cancellationToken);

    public Task<List<ExerciseModel>> GetPickableAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Exercises_GetPickable",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapExercise, cancellationToken),
            cancellationToken);

    public async Task<ExerciseModel> CreateCustomAsync(
        Guid userId, string name, string muscleGroup, string equipmentType, bool isCompound,
        CancellationToken cancellationToken = default) =>
        await sqlExecutor.QueryAsync(
            "dbo.usp_Exercises_CreateCustom",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@Name", name),
                SqlParameterBuilder.Create("@MuscleGroup", muscleGroup),
                SqlParameterBuilder.Create("@EquipmentType", equipmentType),
                SqlParameterBuilder.Create("@IsCompound", isCompound)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapExercise, cancellationToken),
            cancellationToken) ?? throw new InvalidOperationException("usp_Exercises_CreateCustom did not return a row.");

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

    /// <summary>The search's keyword groups as the <c>[{"g":0,"t":"fly"}, ...]</c>
    /// rows the proc's OPENJSON reads - one row per spelling, tagged with the
    /// typed word it stands for. NULL when nothing searchable was typed.</summary>
    private static string? ToTermsJson(string? searchText)
    {
        var groups = ExerciseSearchTerms.Parse(searchText);
        if (groups.Count == 0) return null;
        return JsonSerializer.Serialize(groups.SelectMany((terms, index) =>
            terms.Select(term => new { g = index, t = term })));
    }
}
