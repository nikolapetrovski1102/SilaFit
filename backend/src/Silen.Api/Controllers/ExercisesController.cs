using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>Exercise search, backing the split builder's exercise picker and the
/// live-workout swap/add sheet. Open to any authenticated tier.</summary>
[ApiController]
[Route("api/exercises")]
[Authorize]
public sealed class ExercisesController(IExercisesService exercisesService, ILogger<ExercisesController> logger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Search([FromQuery] string? muscleGroup, [FromQuery] string? search, CancellationToken cancellationToken)
    {
        var result = await exercisesService.SearchAsync(muscleGroup, search, cancellationToken);
        return result.ToActionResult(logger);
    }

    /// <summary>Personalised picks for the caller, best first, optionally narrowed to
    /// the muscle groups a custom split day points at (comma-separated, in priority
    /// order). Builds the "suggested for you" list in the split builder.</summary>
    [HttpGet("suggestions")]
    public async Task<IActionResult> Suggestions(
        [FromQuery] string? muscleGroups,
        [FromQuery] int? limit,
        CancellationToken cancellationToken)
    {
        var result = await exercisesService.SuggestAsync(
            User.GetUserIdOrNull(), ParseMuscleGroups(muscleGroups), limit ?? 12, cancellationToken);

        return result.ToActionResult(logger);
    }

    /// <summary>Splits a comma-separated muscle-group filter into the catalogue's
    /// coarse group names, dropping blanks/duplicates so an empty value behaves
    /// like no filter rather than matching nothing.</summary>
    private static IReadOnlyList<string>? ParseMuscleGroups(string? csv)
    {
        if (string.IsNullOrWhiteSpace(csv))
        {
            return null;
        }

        var groups = csv
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(group => group.ToLowerInvariant())
            .Distinct()
            .ToList();

        return groups.Count == 0 ? null : groups;
    }
}
