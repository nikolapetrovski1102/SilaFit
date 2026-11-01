using System.Text.Json;
using System.Text.Json.Nodes;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;

namespace Silen.Services.Helpers;

/// <summary>A split or diet plan read out of a trainer's document, ready for the import procedure.</summary>
/// <param name="DaysJson">The days in the shape usp_Admin_Split_ImportGenerated / usp_Admin_DietPlan_ImportGenerated read.</param>
public sealed record ImportedProgram(
    string Name, string Level, string? Description, int DurationDays, int DayCount, string DaysJson);

/// <summary>
/// Turns the model's structured answer into what the import procedures take: day
/// numbers clamped to the 26-week range and de-duplicated, reps and macros made
/// sane, and every exercise matched to the library where it plausibly exists, so
/// a document that says "Barbell Bench Press" lands on the library's exercise
/// instead of creating a near-duplicate.
///
/// Pure and static, so the shape rules are testable without the AI call.
/// </summary>
public static class TrainerDocumentImportMapper
{
    public const int MaxDays = 182;

    private static readonly HashSet<string> Levels = new(StringComparer.OrdinalIgnoreCase) { "Beginner", "Intermediate", "Advanced" };
    private static readonly HashSet<string> MealTypes = new(StringComparer.OrdinalIgnoreCase) { "Breakfast", "Lunch", "Dinner", "Snack" };

    /// <summary>Builds the split import from the model's JSON (see TrainerDocumentAiImporter.SplitSchema).</summary>
    public static ImportedProgram MapSplit(string aiJson, IReadOnlyList<AdminExerciseModel> library, string? titleHint)
    {
        var root = Parse(aiJson);
        var lookup = BuildLibraryLookup(library);
        var closeMatchPool = library
            .Select(e => new ExerciseModel { ExerciseId = e.ExerciseId, Name = e.Name, MuscleGroup = e.MuscleGroup })
            .ToList();

        var days = new JsonArray();
        var seen = new HashSet<int>();
        foreach (var day in Array(root, "days"))
        {
            var dayIndex = Int(day, "dayIndex");
            if (dayIndex is null or < 1 or > MaxDays || !seen.Add(dayIndex.Value))
            {
                continue;
            }

            var exercises = new JsonArray();
            foreach (var exercise in Array(day, "exercises"))
            {
                var name = Text(exercise, "name", 150);
                if (name is null)
                {
                    continue;
                }

                var muscleGroup = NormalizeMuscleGroup(Text(exercise, "muscleGroup", 20));
                var match = MatchExercise(Text(exercise, "libraryName", 150), name, muscleGroup, lookup, closeMatchPool);
                var repsLow = Math.Clamp(Int(exercise, "repsLow") ?? 8, 1, 100);
                var repsHigh = Math.Clamp(Int(exercise, "repsHigh") ?? repsLow, repsLow, 100);

                exercises.Add(new JsonObject
                {
                    ["exerciseId"] = match?.ExerciseId.ToString(),
                    ["name"] = match?.Name ?? name,
                    ["muscleGroup"] = match?.MuscleGroup ?? muscleGroup,
                    ["sets"] = Math.Clamp(Int(exercise, "sets") ?? 3, 1, 10),
                    ["repsLow"] = repsLow,
                    ["repsHigh"] = repsHigh,
                    ["notes"] = Text(exercise, "notes", 300)
                });
            }

            var isRest = Bool(day, "isRestDay") ?? false;
            if (!isRest && exercises.Count == 0)
            {
                // A training day the model couldn't fill is a rest day in practice;
                // saying so beats an empty workout the user can't start.
                isRest = true;
            }

            days.Add(new JsonObject
            {
                ["dayIndex"] = dayIndex.Value,
                ["title"] = Text(day, "title", 100) ?? (isRest ? "Rest" : $"Day {dayIndex.Value}"),
                ["focusLabel"] = Text(day, "focusLabel", 100),
                ["estimatedMinutes"] = isRest ? null : Math.Clamp(Int(day, "estimatedMinutes") ?? 60, 10, 240),
                ["isRestDay"] = isRest,
                ["exercises"] = exercises
            });
        }

        if (!days.Any(d => d!["isRestDay"]!.GetValue<bool>() == false))
        {
            throw new ValidationException("AI split import found no training days.",
                "AI couldn't find a workout program in that document. Check it describes exercises, sets and reps.");
        }

        var level = Text(root, "level", 20) is { } rawLevel && Levels.Contains(rawLevel)
            ? Levels.First(l => l.Equals(rawLevel, StringComparison.OrdinalIgnoreCase))
            : "Intermediate";

        return new ImportedProgram(
            ProgramName(root, titleHint, "Imported split"),
            level,
            Text(root, "description", 1000),
            DurationFor(days),
            days.Count,
            days.ToJsonString());
    }

    /// <summary>Builds the diet plan import from the model's JSON (see TrainerDocumentAiImporter.DietPlanSchema).</summary>
    public static ImportedProgram MapDietPlan(string aiJson, string? titleHint)
    {
        var root = Parse(aiJson);
        var days = new JsonArray();
        var seen = new HashSet<int>();
        foreach (var day in Array(root, "days"))
        {
            var dayIndex = Int(day, "dayIndex");
            if (dayIndex is null or < 1 or > MaxDays || !seen.Add(dayIndex.Value))
            {
                continue;
            }

            var meals = new JsonArray();
            foreach (var meal in Array(day, "meals"))
            {
                var title = Text(meal, "title", 200);
                if (title is null)
                {
                    continue;
                }

                var mealType = Text(meal, "mealType", 20) is { } rawType && MealTypes.Contains(rawType)
                    ? MealTypes.First(t => t.Equals(rawType, StringComparison.OrdinalIgnoreCase))
                    : "Snack";

                meals.Add(new JsonObject
                {
                    ["mealType"] = mealType,
                    ["title"] = title,
                    ["description"] = Text(meal, "description", 500),
                    ["calories"] = Math.Clamp(Int(meal, "calories") ?? 0, 0, 5000),
                    ["protein"] = Math.Clamp(Int(meal, "protein") ?? 0, 0, 500),
                    ["carbs"] = Math.Clamp(Int(meal, "carbs") ?? 0, 0, 1000),
                    ["fats"] = Math.Clamp(Int(meal, "fats") ?? 0, 0, 500),
                    ["ingredients"] = Lines(meal, "ingredients", 300, 40),
                    ["steps"] = Lines(meal, "steps", 1000, 30)
                });
            }

            if (meals.Count == 0)
            {
                continue;
            }

            days.Add(new JsonObject
            {
                ["dayIndex"] = dayIndex.Value,
                ["title"] = Text(day, "title", 100) ?? $"Day {dayIndex.Value}",
                ["meals"] = meals
            });
        }

        if (days.Count == 0)
        {
            throw new ValidationException("AI diet plan import found no meals.",
                "AI couldn't find a meal plan in that document. Check it lists meals per day.");
        }

        return new ImportedProgram(
            ProgramName(root, titleHint, "Imported diet plan"),
            "Intermediate",
            Text(root, "description", 1000),
            DurationFor(days),
            days.Count,
            days.ToJsonString());
    }

    /// <summary>Whole weeks covering the last day, so the rotation (anchored to the
    /// activation Monday) lines week 2 up with the second Monday.</summary>
    public static int DurationFor(JsonArray days)
    {
        var lastDay = days.Max(d => d!["dayIndex"]!.GetValue<int>());
        return Math.Min(MaxDays, (int)Math.Ceiling(lastDay / 7.0) * 7);
    }

    /// <summary>Library match for one document exercise: the model's pick by exact name,
    /// then the document's own wording by exact name, then the closest library name in
    /// the same muscle group. Null means "create it".</summary>
    public static AdminExerciseModel? MatchExercise(
        string? libraryName,
        string documentName,
        string muscleGroup,
        IReadOnlyDictionary<string, AdminExerciseModel> lookup,
        IReadOnlyList<ExerciseModel> closeMatchPool)
    {
        if (libraryName is not null && lookup.TryGetValue(NormalizeName(libraryName), out var byPick))
        {
            return byPick;
        }

        if (lookup.TryGetValue(NormalizeName(documentName), out var byName))
        {
            return byName;
        }

        var close = ExerciseCloseMatches.Find(closeMatchPool.Where(e => e.MuscleGroup == muscleGroup), documentName, 1);
        return close.Count == 1 && lookup.TryGetValue(NormalizeName(close[0].Name), out var byClose) ? byClose : null;
    }

    public static IReadOnlyDictionary<string, AdminExerciseModel> BuildLibraryLookup(IReadOnlyList<AdminExerciseModel> library)
    {
        var lookup = new Dictionary<string, AdminExerciseModel>(StringComparer.Ordinal);
        foreach (var exercise in library)
        {
            lookup.TryAdd(NormalizeName(exercise.Name), exercise);
        }
        return lookup;
    }

    public static string NormalizeName(string name) =>
        string.Join(' ', name.ToLowerInvariant()
            .Replace('-', ' ')
            .Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));

    private static string NormalizeMuscleGroup(string? raw) =>
        raw?.Trim().ToLowerInvariant() switch
        {
            "chest" or "back" or "legs" or "shoulders" or "arms" or "core" => raw.Trim().ToLowerInvariant(),
            "glutes" or "hamstrings" or "quads" or "calves" => "legs",
            "biceps" or "triceps" or "forearms" => "arms",
            "abs" or "abdominals" => "core",
            "delts" => "shoulders",
            "lats" or "traps" => "back",
            _ => "core"
        };

    private static string ProgramName(JsonNode root, string? titleHint, string fallback) =>
        Text(root, "name", 100) ?? (string.IsNullOrWhiteSpace(titleHint) ? fallback : titleHint.Trim()[..Math.Min(100, titleHint.Trim().Length)]);

    private static JsonNode Parse(string aiJson)
    {
        try
        {
            return JsonNode.Parse(aiJson) ?? throw new JsonException("null root");
        }
        catch (JsonException exception)
        {
            throw new ConflictException($"AI import returned unparseable JSON: {exception.Message}",
                "AI couldn't read that document right now. Try again, or attach it without AI.");
        }
    }

    private static IEnumerable<JsonNode> Array(JsonNode node, string property) =>
        node[property] is JsonArray array ? array.Where(item => item is JsonObject).Select(item => item!) : [];

    private static string? Text(JsonNode node, string property, int maxLength)
    {
        if (node[property] is not JsonValue value || !value.TryGetValue<string>(out var text))
        {
            return null;
        }

        text = text.Trim();
        if (text.Length == 0)
        {
            return null;
        }
        return text.Length > maxLength ? text[..maxLength] : text;
    }

    private static int? Int(JsonNode node, string property)
    {
        if (node[property] is not JsonValue value)
        {
            return null;
        }
        if (value.TryGetValue<int>(out var number))
        {
            return number;
        }
        if (value.TryGetValue<double>(out var real) && double.IsFinite(real))
        {
            return (int)Math.Round(Math.Clamp(real, int.MinValue, int.MaxValue));
        }
        return null;
    }

    private static bool? Bool(JsonNode node, string property) =>
        node[property] is JsonValue value && value.TryGetValue<bool>(out var flag) ? flag : null;

    private static JsonArray Lines(JsonNode node, string property, int maxLength, int maxCount)
    {
        var lines = new JsonArray();
        if (node[property] is not JsonArray array)
        {
            return lines;
        }

        foreach (var item in array)
        {
            if (item is JsonValue value && value.TryGetValue<string>(out var text) && !string.IsNullOrWhiteSpace(text))
            {
                text = text.Trim();
                lines.Add(text.Length > maxLength ? text[..maxLength] : text);
                if (lines.Count == maxCount)
                {
                    break;
                }
            }
        }
        return lines;
    }
}
