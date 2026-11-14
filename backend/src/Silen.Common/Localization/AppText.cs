using System.Text.RegularExpressions;

namespace Silen.Common.Localization;

/// <summary>
/// Server-side counterpart of the Flutter app's <c>tr()</c>: user-facing
/// messages are written in English in code and looked up here by that exact
/// English text ("gettext style"). A message with no translation is returned
/// unchanged, so nothing ever shows a key or an empty string.
///
/// Only text written for the person reading it goes through here. Content
/// (exercise, meal and food names, plan names a user or trainer typed) stays
/// as stored.
///
/// The language of the current API request comes from its Accept-Language
/// header (see <c>RequestLanguageMiddleware</c>). Work with no request behind it,
/// such as scheduled pushes, passes the user's stored language explicitly.
/// </summary>
public static class AppText
{
    public const string English = "en";
    public const string Macedonian = "mk";

    private static readonly AsyncLocal<string?> RequestLanguageSlot = new();

    /// <summary>The language of the request being handled, or <see cref="English"/>
    /// outside a request.</summary>
    public static string CurrentLanguage => RequestLanguageSlot.Value ?? English;

    /// <summary>Sets <see cref="CurrentLanguage"/> for the rest of this async flow.</summary>
    public static void SetRequestLanguage(string? language) =>
        RequestLanguageSlot.Value = Normalize(language);

    /// <summary>Any language tag ("mk", "mk-MK", "en-US", null) mapped onto a
    /// supported language: Macedonian, or English for everything else.</summary>
    public static string Normalize(string? language) =>
        language is not null && language.Trim().StartsWith(Macedonian, StringComparison.OrdinalIgnoreCase)
            ? Macedonian
            : English;

    /// <summary>Translates <paramref name="english"/> into the current request's language.</summary>
    public static string Translate(string english) => Translate(english, CurrentLanguage);

    /// <summary>Translates <paramref name="english"/> into <paramref name="language"/>.</summary>
    public static string Translate(string english, string? language)
    {
        if (string.IsNullOrEmpty(english) || Normalize(language) != Macedonian)
        {
            return english;
        }

        if (MacedonianMessages.Exact.TryGetValue(english, out var exact))
        {
            return exact;
        }

        foreach (var template in Templates.Value)
        {
            var match = template.Pattern.Match(english);
            if (match.Success)
            {
                return template.Fill(match);
            }
        }

        return english;
    }

    private static readonly Lazy<IReadOnlyList<Template>> Templates = new(() =>
        MacedonianMessages.Templates.Select(pair => new Template(pair.English, pair.Macedonian)).ToList());

    /// <summary>A message with values baked in, e.g. "A meal can hold up to {0} foods.".
    /// The English form becomes an anchored regex; each {n} captures the value,
    /// which is put back into the same {n} of the Macedonian form.</summary>
    private sealed class Template
    {
        private static readonly Regex Placeholder = new(@"\\\{(\d+)\}", RegexOptions.Compiled);

        private readonly string _macedonian;

        public Template(string english, string macedonian)
        {
            _macedonian = macedonian;
            var pattern = Placeholder.Replace(Regex.Escape(english), m => $"(?<p{m.Groups[1].Value}>.+?)");
            Pattern = new Regex("^" + pattern + "$", RegexOptions.Compiled | RegexOptions.Singleline);
        }

        public Regex Pattern { get; }

        public string Fill(Match match)
        {
            var result = _macedonian;
            foreach (Group group in match.Groups)
            {
                if (group.Name.StartsWith('p'))
                {
                    result = result.Replace("{" + group.Name[1..] + "}", group.Value);
                }
            }

            return result;
        }
    }
}
