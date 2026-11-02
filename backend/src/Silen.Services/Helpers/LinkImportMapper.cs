using System.Text.Json;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Common.Models;

namespace Silen.Services.Helpers;

/// <summary>
/// Turns the model's reading of a post caption into what the app shows: exercises
/// matched to the caller's pickable library (catalogue plus their own customs) with
/// sane sets and reps, or meal ingredients clamped into what a real food can be.
///
/// Pure and static, so the rules are testable without the AI call.
/// </summary>
public static class LinkImportMapper
{
    public const string Workout = "workout";
    public const string Meal = "meal";
    public const string Other = "other";

    private const int MaxExercises = 15;
    private const int MaxTitleLength = 80;
    private const int MaxNameLength = 120;
    private const decimal MaxItemGrams = 2000;
    private const decimal MaxKcalPer100G = 900;
    private const decimal MaxGramsPer100G = 100;

    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };

    /// <summary>Reads the model's JSON. Throws <see cref="JsonException"/> when it isn't the schema's shape.</summary>
    public static AiLinkResult Parse(string json) =>
        JsonSerializer.Deserialize<AiLinkResult>(json, JsonOptions) ?? throw new JsonException("Link import response deserialized to null.");

    public static string Serialize(AiLinkResult result) => JsonSerializer.Serialize(result);

    /// <summary>The kind the result will be shown as: a workout without exercises or a meal
    /// without ingredients is nothing the app can import, so it's "other".</summary>
    public static string KindOf(AiLinkResult ai) => ai.Kind switch
    {
        Workout when (ai.Exercises ?? []).Any(e => !string.IsNullOrWhiteSpace(e.Name)) => Workout,
        Meal when (ai.Items ?? []).Any(i => !string.IsNullOrWhiteSpace(i.Name)) => Meal,
        _ => Other
    };

    public static List<LinkImportExerciseDto> MapExercises(AiLinkResult ai, IReadOnlyList<ExerciseModel> library)
    {
        var lookup = new Dictionary<string, ExerciseModel>(StringComparer.Ordinal);
        foreach (var exercise in library)
        {
            lookup.TryAdd(TrainerDocumentImportMapper.NormalizeName(exercise.Name), exercise);
        }

        var result = new List<LinkImportExerciseDto>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var exercise in ai.Exercises ?? [])
        {
            var name = Trim(exercise.Name, MaxNameLength);
            if (name is null)
            {
                continue;
            }

            var muscleGroup = ExerciseMuscleGroup(exercise.MuscleGroup);
            var match = Match(exercise.LibraryName, name, muscleGroup, lookup, library);

            // The same move listed twice ("superset with... then back to...") is one exercise.
            var key = match?.ExerciseId.ToString() ?? TrainerDocumentImportMapper.NormalizeName(name);
            if (!seen.Add(key))
            {
                continue;
            }

            var repsLow = Math.Clamp(exercise.RepsLow is > 0 ? exercise.RepsLow : 8, 1, 100);
            var repsHigh = Math.Clamp(exercise.RepsHigh is > 0 ? exercise.RepsHigh : repsLow, repsLow, 100);
            result.Add(new LinkImportExerciseDto
            {
                ExerciseId = match?.ExerciseId,
                Name = match?.Name ?? name,
                MuscleGroup = match?.MuscleGroup ?? muscleGroup,
                Sets = Math.Clamp(exercise.Sets is > 0 ? exercise.Sets : 3, 1, 10),
                RepsLow = repsLow,
                RepsHigh = repsHigh
            });

            if (result.Count == MaxExercises)
            {
                break;
            }
        }

        return result;
    }

    public static List<FoodScanItemDto> MapMealItems(AiLinkResult ai) =>
        (ai.Items ?? []).Select(SanitizeItem).OfType<FoodScanItemDto>().ToList();

    public static string Title(AiLinkResult ai, string fallback) =>
        Trim(ai.Title, MaxTitleLength) ?? fallback;

    /// <summary>The model's pick by exact library name, then the caption's own wording by exact
    /// name, then the closest library name in the same muscle group. Null means "no match".</summary>
    private static ExerciseModel? Match(
        string? libraryName, string name, string muscleGroup,
        IReadOnlyDictionary<string, ExerciseModel> lookup, IReadOnlyList<ExerciseModel> library)
    {
        if (!string.IsNullOrWhiteSpace(libraryName) && lookup.TryGetValue(TrainerDocumentImportMapper.NormalizeName(libraryName), out var byPick))
        {
            return byPick;
        }

        if (lookup.TryGetValue(TrainerDocumentImportMapper.NormalizeName(name), out var byName))
        {
            return byName;
        }

        var close = ExerciseCloseMatches.Find(library.Where(e => e.MuscleGroup == muscleGroup), name, 1);
        return close.Count == 1 ? close[0] : null;
    }

    private static string ExerciseMuscleGroup(string? raw) =>
        raw?.Trim().ToLowerInvariant() switch
        {
            "chest" or "back" or "legs" or "shoulders" or "arms" or "core" => raw.Trim().ToLowerInvariant(),
            _ => "core"
        };

    /// <summary>The same per-100 g ceilings the photo scan and custom foods are held to, so a
    /// hallucinated value can't reach the user's totals.</summary>
    private static FoodScanItemDto? SanitizeItem(AiLinkItem item)
    {
        var name = Trim(item.Name, MaxNameLength);
        if (name is null)
        {
            return null;
        }

        var protein = Clamp(item.ProteinPer100G, MaxGramsPer100G);
        var carbs = Clamp(item.CarbsPer100G, MaxGramsPer100G);
        var fat = Clamp(item.FatPer100G, MaxGramsPer100G);
        var macroSum = protein + carbs + fat;
        if (macroSum > MaxGramsPer100G)
        {
            var scale = MaxGramsPer100G / macroSum;
            protein *= scale;
            carbs *= scale;
            fat *= scale;
        }

        return new FoodScanItemDto
        {
            Name = name,
            EstimatedGrams = Math.Round(Math.Clamp(item.Grams, 1, MaxItemGrams), 0),
            CaloriesKcal = Math.Round(Clamp(item.KcalPer100G, MaxKcalPer100G), 1),
            ProteinG = Math.Round(protein, 1),
            CarbohydrateG = Math.Round(carbs, 1),
            FatG = Math.Round(fat, 1),
            FiberG = Math.Round(Clamp(item.FiberPer100G, MaxGramsPer100G), 1),
            IsAssumed = item.Assumed,
            Confidence = item.Confidence is "high" or "medium" or "low" ? item.Confidence : "medium"
        };
    }

    private static decimal Clamp(decimal value, decimal max) => Math.Clamp(value, 0, max);

    private static string? Trim(string? value, int maxLength)
    {
        var trimmed = value?.Trim();
        if (string.IsNullOrEmpty(trimmed))
        {
            return null;
        }

        return trimmed.Length > maxLength ? trimmed[..maxLength] : trimmed;
    }

    /// <summary>The model's answer - property names match the json_schema in LinkImportService.</summary>
    public sealed class AiLinkResult
    {
        public string? Kind { get; set; }
        public string? Title { get; set; }
        public string? Notes { get; set; }
        public List<AiLinkExercise>? Exercises { get; set; }
        public List<AiLinkItem>? Items { get; set; }
    }

    public sealed class AiLinkExercise
    {
        public string? Name { get; set; }
        public string? LibraryName { get; set; }
        public string? MuscleGroup { get; set; }
        public int Sets { get; set; }
        public int RepsLow { get; set; }
        public int RepsHigh { get; set; }
    }

    public sealed class AiLinkItem
    {
        public string? Name { get; set; }
        public decimal Grams { get; set; }
        public decimal KcalPer100G { get; set; }
        public decimal ProteinPer100G { get; set; }
        public decimal CarbsPer100G { get; set; }
        public decimal FatPer100G { get; set; }
        public decimal FiberPer100G { get; set; }
        public bool Assumed { get; set; }
        public string? Confidence { get; set; }
    }
}
