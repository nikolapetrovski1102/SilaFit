using System.Text;
using Silen.Common.Models;

namespace Silen.Common.Helpers;

/// <summary>
/// The picker's "did you mean" pass, run only when <c>usp_Exercises_Search</c>
/// found nothing. That search matches substrings, so a typo ("benhc press",
/// "tricpe pushdown", "bulgarain split squat") misses outright; this compares
/// each typed word to each word of every name by edit distance instead, and
/// keeps exercises where at least half the typed words land close to a word in
/// the name.
/// </summary>
public static class ExerciseCloseMatches
{
    /// <summary>Typed words shorter than this must match exactly - one edit
    /// turns "db" or "ez" into almost anything.</summary>
    private const int MinFuzzyLength = 3;

    public static List<ExerciseModel> Find(IEnumerable<ExerciseModel> exercises, string? searchText, int take)
    {
        var groups = ExerciseSearchTerms.Parse(searchText);
        if (groups.Count == 0) return [];

        return exercises
            .Select(exercise => (Exercise: exercise, Score: Score(groups, NameWords(exercise.Name))))
            .Where(match => match.Score.Matched >= 1 && match.Score.Matched * 2 >= groups.Count)
            .OrderByDescending(match => match.Score.Matched)
            .ThenByDescending(match => match.Score.Similarity)
            .ThenBy(match => match.Exercise.Name.Length)
            .ThenBy(match => match.Exercise.Name, StringComparer.OrdinalIgnoreCase)
            .Take(take)
            .Select(match => match.Exercise)
            .ToList();
    }

    private static (int Matched, double Similarity) Score(
        IReadOnlyList<IReadOnlyList<string>> groups, IReadOnlyList<string> nameWords)
    {
        var matched = 0;
        var total = 0.0;
        foreach (var group in groups)
        {
            var best = group.Max(term => nameWords.Max(word => Similarity(term, word)));
            if (best <= 0) continue;
            matched++;
            total += best;
        }
        return (matched, total);
    }

    /// <summary>1 for the same word, down towards 0 as edits pile up; 0 once the
    /// distance is more than a word of that length can plausibly carry as a
    /// typo (1 edit up to 4 letters, 2 up to 7, 3 beyond).</summary>
    private static double Similarity(string typed, string word)
    {
        if (typed == word) return 1;
        if (typed.Length < MinFuzzyLength) return 0;
        if (word.StartsWith(typed, StringComparison.Ordinal)) return 0.9;

        var allowed = typed.Length <= 4 ? 1 : typed.Length <= 7 ? 2 : 3;
        if (Math.Abs(typed.Length - word.Length) > allowed) return 0;

        var distance = EditDistance(typed, word);
        return distance > allowed ? 0 : 1 - (double)distance / Math.Max(typed.Length, word.Length);
    }

    /// <summary>The name's stemmed words, plus each adjacent pair run together so
    /// "pullup" still lines up with "Pull-Up" and "Pull Up".</summary>
    private static List<string> NameWords(string name)
    {
        var words = new List<string>();
        var current = new StringBuilder();
        foreach (var ch in name.ToLowerInvariant())
        {
            if (char.IsLetterOrDigit(ch))
            {
                current.Append(ch);
                continue;
            }
            if (current.Length > 0)
            {
                words.Add(current.ToString());
                current.Clear();
            }
        }
        if (current.Length > 0) words.Add(current.ToString());

        var result = words.Select(ExerciseSearchTerms.Stem).ToList();
        for (var i = 0; i + 1 < words.Count; i++)
        {
            result.Add(ExerciseSearchTerms.Stem(words[i] + words[i + 1]));
        }
        return result.Count == 0 ? [string.Empty] : result;
    }

    /// <summary>Optimal-string-alignment distance: Levenshtein plus adjacent
    /// swaps as one edit, since "benhc" for "bench" is the typical slip.</summary>
    private static int EditDistance(string a, string b)
    {
        var d = new int[a.Length + 1, b.Length + 1];
        for (var i = 0; i <= a.Length; i++) d[i, 0] = i;
        for (var j = 0; j <= b.Length; j++) d[0, j] = j;

        for (var i = 1; i <= a.Length; i++)
        {
            for (var j = 1; j <= b.Length; j++)
            {
                var cost = a[i - 1] == b[j - 1] ? 0 : 1;
                d[i, j] = Math.Min(Math.Min(d[i - 1, j] + 1, d[i, j - 1] + 1), d[i - 1, j - 1] + cost);
                if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1])
                {
                    d[i, j] = Math.Min(d[i, j], d[i - 2, j - 2] + 1);
                }
            }
        }
        return d[a.Length, b.Length];
    }
}
