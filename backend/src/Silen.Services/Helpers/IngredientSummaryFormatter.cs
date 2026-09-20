using System.Globalization;
using System.Text.RegularExpressions;

namespace Silen.Services.Helpers;

/// <summary>
/// Turns free-text recipe lines into a compact weekly ingredient summary. It
/// aggregates only quantities it can parse confidently. Different units are
/// kept as separate measures on the same ingredient line rather than converted.
/// </summary>
public static partial class IngredientSummaryFormatter
{
    private static readonly Dictionary<string, string> UnitAliases = new(StringComparer.OrdinalIgnoreCase)
    {
        ["cup"] = "cup",
        ["cups"] = "cup",
        ["tbsp"] = "tbsp",
        ["tablespoon"] = "tbsp",
        ["tablespoons"] = "tbsp",
        ["tsp"] = "tsp",
        ["teaspoon"] = "tsp",
        ["teaspoons"] = "tsp",
        ["oz"] = "oz",
        ["ounce"] = "oz",
        ["ounces"] = "oz",
        ["lb"] = "lb",
        ["lbs"] = "lb",
        ["pound"] = "lb",
        ["pounds"] = "lb",
        ["g"] = "g",
        ["gram"] = "g",
        ["grams"] = "g",
        ["kg"] = "kg",
        ["ml"] = "ml",
        ["l"] = "l",
        ["can"] = "can",
        ["cans"] = "can",
        ["scoop"] = "scoop",
        ["scoops"] = "scoop"
    };

    public static List<string> Summarize(IEnumerable<string> ingredients)
    {
        var ordered = new List<Aggregate>();
        var indexes = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        foreach (var raw in ingredients)
        {
            var trimmed = CollapseWhitespace(raw.Trim());
            if (trimmed.Length == 0)
            {
                continue;
            }

            if (!TryParse(trimmed, out var parsed))
            {
                AddOrIncrementFallback(trimmed, ordered, indexes);
                continue;
            }

            var key = $"quantity:{NormalizeName(parsed.Name)}";
            if (indexes.TryGetValue(key, out var index))
            {
                var current = ordered[index];
                current.AddQuantity(parsed.Unit, parsed.Amount);
                if (LooksPlural(parsed.Name))
                {
                    current.Name = parsed.Name;
                }
            }
            else
            {
                indexes[key] = ordered.Count;
                ordered.Add(Aggregate.Quantity(parsed.Name, parsed.Unit, parsed.Amount));
            }
        }

        return ordered.Select(Format).ToList();
    }

    private static void AddOrIncrementFallback(
        string text,
        List<Aggregate> ordered,
        Dictionary<string, int> indexes)
    {
        var key = $"text:{text}";
        if (indexes.TryGetValue(key, out var index))
        {
            ordered[index].Amount++;
            return;
        }

        indexes[key] = ordered.Count;
        ordered.Add(Aggregate.Fallback(text));
    }

    private static bool TryParse(string text, out ParsedIngredient parsed)
    {
        var match = QuantityPrefix().Match(text);
        if (!match.Success || !TryParseAmount(match.Groups["quantity"].Value, out var amount))
        {
            parsed = default;
            return false;
        }

        var remainder = match.Groups["remainder"].Value.Trim();
        string? unit = null;
        var separator = remainder.IndexOf(' ');
        var firstToken = (separator < 0 ? remainder : remainder[..separator]).TrimEnd(',', '.');
        if (UnitAliases.TryGetValue(firstToken, out var normalizedUnit))
        {
            unit = normalizedUnit;
            remainder = separator < 0 ? string.Empty : remainder[(separator + 1)..].Trim();
            if (remainder.StartsWith("of ", StringComparison.OrdinalIgnoreCase))
            {
                remainder = remainder[3..].Trim();
            }
        }

        if (remainder.Length == 0)
        {
            parsed = default;
            return false;
        }

        parsed = new ParsedIngredient(Capitalize(remainder), unit, amount);
        return true;
    }

    private static bool TryParseAmount(string value, out decimal amount)
    {
        value = value.Trim();
        var unicodeValue = UnicodeFractionValue(value[^1]);
        if (unicodeValue is not null)
        {
            var wholeText = value[..^1].Trim();
            var unicodeWhole = wholeText.Length == 0
                ? 0
                : decimal.Parse(wholeText, CultureInfo.InvariantCulture);
            amount = unicodeWhole + unicodeValue.Value;
            return true;
        }

        var parts = value.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 2 && TryParseFraction(parts[1], out var fraction)
            && decimal.TryParse(parts[0], NumberStyles.Number, CultureInfo.InvariantCulture, out var whole))
        {
            amount = whole + fraction;
            return true;
        }

        if (TryParseFraction(value, out amount))
        {
            return true;
        }

        return decimal.TryParse(value, NumberStyles.Number, CultureInfo.InvariantCulture, out amount);
    }

    private static bool TryParseFraction(string value, out decimal amount)
    {
        var fraction = value.Split('/');
        if (fraction.Length == 2
            && decimal.TryParse(fraction[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var numerator)
            && decimal.TryParse(fraction[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out var denominator)
            && denominator != 0)
        {
            amount = numerator / denominator;
            return true;
        }

        amount = 0;
        return false;
    }

    private static decimal? UnicodeFractionValue(char value) => value switch
    {
        '¼' => 0.25m,
        '½' => 0.5m,
        '¾' => 0.75m,
        '⅓' => 1m / 3m,
        '⅔' => 2m / 3m,
        '⅕' => 0.2m,
        '⅖' => 0.4m,
        '⅗' => 0.6m,
        '⅘' => 0.8m,
        '⅙' => 1m / 6m,
        '⅚' => 5m / 6m,
        '⅛' => 0.125m,
        '⅜' => 0.375m,
        '⅝' => 0.625m,
        '⅞' => 0.875m,
        _ => null
    };

    private static string Format(Aggregate item)
    {
        if (!item.IsQuantity)
        {
            return item.Amount > 1 ? $"{item.Name} ×{item.Amount}" : item.Name;
        }

        var measures = item.Measures.Select(measure =>
        {
            var amount = measure.Amount.ToString("0.##", CultureInfo.InvariantCulture);
            var unit = FormatUnit(measure.Unit, measure.Amount);
            return unit is null ? amount : $"{amount} {unit}";
        });
        return $"{item.Name} ×{string.Join(" + ", measures)}";
    }

    private static string? FormatUnit(string? unit, decimal amount) => unit switch
    {
        "cup" => amount == 1 ? "cup" : "cups",
        "can" => amount == 1 ? "can" : "cans",
        "scoop" => amount == 1 ? "scoop" : "scoops",
        "lb" => amount == 1 ? "lb" : "lbs",
        _ => unit
    };

    private static string NormalizeName(string name)
    {
        var normalized = name.Trim().ToLowerInvariant();
        var words = normalized.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (words.Length == 0)
        {
            return normalized;
        }

        var last = words[^1].TrimEnd(',', '.');
        words[^1] = last.EndsWith("ies", StringComparison.Ordinal) && last.Length > 3
            ? $"{last[..^3]}y"
            : last.EndsWith('s') && !last.EndsWith("ss", StringComparison.Ordinal) && last.Length > 3
                ? last[..^1]
                : last;
        return string.Join(' ', words);
    }

    private static bool LooksPlural(string name)
    {
        var last = name.Split(' ', StringSplitOptions.RemoveEmptyEntries).LastOrDefault() ?? string.Empty;
        return last.EndsWith('s') && !last.EndsWith("ss", StringComparison.Ordinal);
    }

    private static string Capitalize(string value) => value.Length == 0
        ? value
        : $"{char.ToUpperInvariant(value[0])}{value[1..]}";

    private static string CollapseWhitespace(string value) => Whitespace().Replace(value, " ");

    [GeneratedRegex(@"^(?<quantity>(?:\d+\s+)?[¼½¾⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞]|\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)\s*(?<remainder>.+)$")]
    private static partial Regex QuantityPrefix();

    [GeneratedRegex(@"\s+")]
    private static partial Regex Whitespace();

    private readonly record struct ParsedIngredient(string Name, string? Unit, decimal Amount);

    private sealed class Aggregate
    {
        private readonly Dictionary<string, int> measureIndexes = new(StringComparer.OrdinalIgnoreCase);

        private Aggregate(string name, bool isQuantity)
        {
            Name = name;
            IsQuantity = isQuantity;
        }

        public string Name { get; set; }
        public decimal Amount { get; set; }
        public bool IsQuantity { get; }
        public List<Measure> Measures { get; } = [];

        public static Aggregate Quantity(string name, string? unit, decimal amount)
        {
            var aggregate = new Aggregate(name, isQuantity: true);
            aggregate.AddQuantity(unit, amount);
            return aggregate;
        }

        public static Aggregate Fallback(string name) => new(name, isQuantity: false) { Amount = 1 };

        public void AddQuantity(string? unit, decimal amount)
        {
            var key = unit ?? string.Empty;
            if (measureIndexes.TryGetValue(key, out var index))
            {
                var current = Measures[index];
                Measures[index] = current with { Amount = current.Amount + amount };
                return;
            }

            measureIndexes[key] = Measures.Count;
            Measures.Add(new Measure(unit, amount));
        }
    }

    private readonly record struct Measure(string? Unit, decimal Amount);
}
