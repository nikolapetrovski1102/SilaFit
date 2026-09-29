using System.Text;

namespace Silen.Common.Helpers;

/// <summary>
/// Turns a typed exercise search ("shoulder fly", "DB flyes", "pull-ups") into
/// keyword groups for <c>usp_Exercises_Search</c>. Each group is one typed word
/// plus the spellings it should also match - so "fly" still finds "Shoulder
/// Cable Flys", "flyes" finds "Rear Delt Fly" and "db" finds "Dumbbell ...".
/// The proc ranks exercises by how many groups they hit, rather than needing
/// the whole query as one exact substring of the name.
/// </summary>
public static class ExerciseSearchTerms
{
    /// <summary>Beyond this many words the query is a sentence, not a search.</summary>
    private const int MaxGroups = 6;

    private static readonly HashSet<string> StopWords =
    [
        "a", "an", "and", "the", "with", "on", "for", "of", "to", "in", "at", "using",
        "exercise", "exercises", "movement", "workout"
    ];

    /// <summary>Gym shorthand and near-synonyms, keyed by the stemmed word. The
    /// word itself is always kept as well; muscle words also map to the
    /// catalogue's coarse muscle group so "delt fly" still reaches exercises
    /// named after the shoulder.</summary>
    private static readonly Dictionary<string, string[]> Synonyms = new()
    {
        ["db"] = ["dumbbell"],
        ["bb"] = ["barbell"],
        ["kb"] = ["kettlebell"],
        ["ez"] = ["ez bar", "ez-bar"],
        ["bw"] = ["bodyweight"],
        ["flye"] = ["fly"],
        ["ohp"] = ["overhead press", "shoulder press"],
        ["rdl"] = ["romanian deadlift"],
        ["sldl"] = ["stiff leg deadlift"],
        ["shoulder"] = ["delt"],
        ["delt"] = ["shoulder"],
        ["deltoid"] = ["delt", "shoulder"],
        ["pec"] = ["chest"],
        ["chest"] = ["pec"],
        ["lat"] = ["back"],
        ["trap"] = ["shrug"],
        ["abdominal"] = ["core", "crunch"],
        ["oblique"] = ["core"],
        ["bicep"] = ["curl", "arms"],
        ["tricep"] = ["arms", "extension", "pushdown"],
        ["quad"] = ["legs"],
        ["hamstring"] = ["legs"],
        ["glute"] = ["legs", "hip thrust"],
        ["calf"] = ["legs"],
        ["calve"] = ["calf", "legs"],
        ["leg"] = ["legs"],
        ["arm"] = ["arms"]
    };

    /// <summary>Keyword groups for <paramref name="searchText"/>, lowercased,
    /// de-pluralised and de-duplicated; empty when nothing searchable was
    /// typed (blank, punctuation or only filler words).</summary>
    public static IReadOnlyList<IReadOnlyList<string>> Parse(string? searchText)
    {
        if (string.IsNullOrWhiteSpace(searchText)) return [];

        var groups = new List<IReadOnlyList<string>>();
        var seen = new HashSet<string>();
        foreach (var word in SplitWords(searchText))
        {
            if (word.Length < 2 && !char.IsDigit(word[0])) continue;
            if (StopWords.Contains(word)) continue;

            var stem = Stem(word);
            if (!seen.Add(stem)) continue;

            var alternatives = new List<string> { stem };
            if (Synonyms.TryGetValue(stem, out var extra))
            {
                alternatives.AddRange(extra.Where(e => !alternatives.Contains(e)));
            }
            groups.Add(alternatives);
            if (groups.Count == MaxGroups) break;
        }
        return groups;
    }

    /// <summary>Lowercase letter/digit runs. Hyphens and other punctuation split
    /// words, so "pull-up" is "pull" + "up"; the proc also compares against the
    /// name with spaces and hyphens removed, which is how "pullup" finds it.</summary>
    private static IEnumerable<string> SplitWords(string text)
    {
        var current = new StringBuilder();
        foreach (var ch in text.ToLowerInvariant())
        {
            if (char.IsLetterOrDigit(ch))
            {
                current.Append(ch);
                continue;
            }
            if (current.Length > 0)
            {
                yield return current.ToString();
                current.Clear();
            }
        }
        if (current.Length > 0) yield return current.ToString();
    }

    /// <summary>A light English de-pluralisation - enough that the stem is a
    /// substring of both the singular and plural spellings ("flies" -> "fly",
    /// "presses" -> "press", "lunges" -> "lunge", "rows" -> "row"). Short words
    /// are left alone, and "ab"/"abs" become "abdominal" - as a bare substring
    /// "ab" would match every "Cable ..." exercise.</summary>
    internal static string Stem(string word)
    {
        if (word is "ab" or "abs") return "abdominal";
        if (word.Length <= 3) return word;
        if (word.EndsWith("ies")) return word[..^3] + "y";
        if (word.EndsWith("sses") || word.EndsWith("shes") || word.EndsWith("ches") || word.EndsWith("xes"))
            return word[..^2];
        if (word.EndsWith("yes")) return word[..^2];
        if (word.EndsWith("ss") || word.EndsWith("us")) return word;
        if (word.EndsWith('s')) return word[..^1];
        return word;
    }
}
