using System.Text.RegularExpressions;

namespace Silen.Services.Helpers;

/// <summary>
/// Auto-assigned hero artwork for splits users build themselves (in-app wizard,
/// split builder, AI weekly generation). The artwork comes in a dark and a light
/// variant, so what's stored is a theme-neutral key; the API serves both variants
/// from Silen.Api/StaticAssets at <c>/api/static/splits/{dark|light}/{key}.jpg</c>
/// and the app picks one - see frontend/lib/features/splits/widgets/split_hero_image.dart.
/// The curated category wins; a "Custom" split falls back to keywords in its
/// name/description, then to the generic custom-protocol artwork.
/// </summary>
public static partial class SplitHeroImages
{
    public const string Prefix = "asset:splits/";

    public const string PushPullLegs = Prefix + "push_pull_legs";
    public const string UpperLower = Prefix + "upper_lower";
    public const string BroSplit = Prefix + "bro_split";
    public const string Strength = Prefix + "strength";
    public const string Hypertrophy = Prefix + "hypertrophy";
    public const string Conditioning = Prefix + "conditioning";
    public const string General = Prefix + "general";
    public const string Custom = Prefix + "custom";

    /// <summary>
    /// Keeps an explicit http(s) image the caller supplied; otherwise (nothing
    /// sent, or a previously auto-assigned key) re-derives the artwork so a
    /// header save can never wipe it and a rename can refine it.
    /// </summary>
    public static string Resolve(string? requested, string? category, string? name, string? description)
    {
        var trimmed = requested?.Trim();
        if (!string.IsNullOrEmpty(trimmed) && !trimmed.StartsWith(Prefix, StringComparison.Ordinal))
        {
            return trimmed;
        }

        return ForSplit(category, name, description);
    }

    public static string ForSplit(string? category, string? name, string? description) => category switch
    {
        "PushPullLegs" or "ArnoldSplit" => PushPullLegs,
        "UpperLower" or "PHUL" => UpperLower,
        "BroSplit" => BroSplit,
        "Powerlifting" => Strength,
        "PHAT" or "GluteFocus" => Hypertrophy,
        "Circuit" or "Calisthenics" => Conditioning,
        "FullBody" => General,
        _ => FromText($"{name} {description}")
    };

    private static string FromText(string text)
    {
        if (PushPullLegsWords().IsMatch(text)) return PushPullLegs;
        if (UpperLowerWords().IsMatch(text)) return UpperLower;
        if (StrengthWords().IsMatch(text)) return Strength;
        if (ConditioningWords().IsMatch(text)) return Conditioning;
        if (HypertrophyWords().IsMatch(text)) return Hypertrophy;
        if (BroSplitWords().IsMatch(text)) return BroSplit;
        if (GeneralWords().IsMatch(text)) return General;
        return Custom;
    }

    [GeneratedRegex(@"\b(ppl|push[\s/&,+-]*pull|arnold)\b", RegexOptions.IgnoreCase)]
    private static partial Regex PushPullLegsWords();

    [GeneratedRegex(@"\b(upper[\s/&,+-]*lower|phul)\b", RegexOptions.IgnoreCase)]
    private static partial Regex UpperLowerWords();

    [GeneratedRegex(@"\b(strength|strong(er)?|power(lifting)?|5\s*x\s*5|5/3/1|deadlifts?|squats?|compound)\b", RegexOptions.IgnoreCase)]
    private static partial Regex StrengthWords();

    [GeneratedRegex(@"\b(hiit|conditioning|cardio|circuits?|athletic|functional|crossfit|calisthenics|endurance|shred|cut(ting)?|fat[\s-]*loss|lean)\b", RegexOptions.IgnoreCase)]
    private static partial Regex ConditioningWords();

    [GeneratedRegex(@"\b(hypertrophy|bodybuilding|mass|bulk(ing)?|muscle|size|gains|aesthetics?|phat|glutes?)\b", RegexOptions.IgnoreCase)]
    private static partial Regex HypertrophyWords();

    [GeneratedRegex(@"\b(bro|body[\s-]*part|chest|arms?|biceps?|triceps?|shoulders?)\b", RegexOptions.IgnoreCase)]
    private static partial Regex BroSplitWords();

    [GeneratedRegex(@"\b(full[\s-]*body|total[\s-]*body|general|fitness|beginners?|starter|basics?)\b", RegexOptions.IgnoreCase)]
    private static partial Regex GeneralWords();
}
