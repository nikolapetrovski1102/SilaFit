using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

internal sealed record FoodNutritionRow(
    string Name,
    string? BrandName,
    string? Barcode,
    string? DataType,
    string SourceName,
    string SourceFoodId,
    string? SourceUrl,
    decimal? ServingSizeG,
    decimal? CaloriesKcal,
    decimal? ProteinG,
    decimal? CarbohydrateG,
    decimal? FatG,
    decimal? FiberG,
    decimal? SugarG,
    decimal? SodiumMg,
    bool IsBranded)
{
    private static readonly Regex Whitespace = new(@"\s+", RegexOptions.Compiled);
    private static readonly Regex Punctuation = new(@"[^\p{L}\p{N}]+", RegexOptions.Compiled);

    public string NormalizedName => Normalize(Name);

    public byte[] ContentHash
    {
        get
        {
            var identity = string.Join('|',
                NormalizedName,
                Normalize(BrandName),
                Normalize(Barcode),
                Format(CaloriesKcal),
                Format(ProteinG),
                Format(CarbohydrateG),
                Format(FatG),
                Format(FiberG),
                Format(SugarG),
                Format(SodiumMg));
            return SHA256.HashData(Encoding.UTF8.GetBytes(identity));
        }
    }

    public bool HasUsefulMacros => CaloriesKcal is not null || ProteinG is not null || CarbohydrateG is not null || FatG is not null;

    /// <summary>The per-row rules of dbo.FoodNutrition_Prune (FoodNutrition.sql),
    /// applied before insert so the importer never writes rows the prune would
    /// delete - keep the two in step. Generic sources always pass; duplicates
    /// need the whole table, so only the prune catches those.</summary>
    public bool IsCatalogQuality
    {
        get
        {
            if (!IsBranded) return true;
            if (CaloriesKcal is not { } kcal || ProteinG is not { } protein
                || CarbohydrateG is not { } carbs || FatG is not { } fat) return false;

            var atwater = 4 * protein + 4 * carbs + 9 * fat;
            if (atwater - kcal > 50 && kcal < 0.5m * atwater) return false;
            if (kcal - atwater > 300) return false;
            if (SourceName == "Open Food Facts" && string.IsNullOrWhiteSpace(BrandName)) return false;
            return NormalizedName.Any(character => character is not (>= '0' and <= '9' or ' '));
        }
    }

    public FoodNutritionRow Sanitize() => this with
    {
        ServingSizeG = InRange(ServingSizeG, 0, 1_000_000),
        CaloriesKcal = InRange(CaloriesKcal, 0, 1_000),
        ProteinG = InRange(ProteinG, 0, 100),
        CarbohydrateG = InRange(CarbohydrateG, 0, 100),
        FatG = InRange(FatG, 0, 100),
        FiberG = InRange(FiberG, 0, 100),
        SugarG = InRange(SugarG, 0, 100),
        SodiumMg = InRange(SodiumMg, 0, 100_000)
    };

    public static string Normalize(string? value) =>
        Whitespace.Replace(Punctuation.Replace((value ?? string.Empty).Trim().ToLowerInvariant(), " "), " ").Trim();

    private static string Format(decimal? value) =>
        value is null ? string.Empty : decimal.Round(value.Value, 3).ToString("0.###", CultureInfo.InvariantCulture);

    private static decimal? InRange(decimal? value, decimal minimum, decimal maximum) =>
        value is >= 0 && value >= minimum && value <= maximum ? value : null;
}
