using System.Text.RegularExpressions;

namespace Silen.Services.Helpers;

/// <summary>
/// Recognises TikTok links in whatever the share sheet handed the app - TikTok shares
/// a line of text with the link at the end ("Check out this video! https://vm.tiktok.com/ZM...")
/// - and pulls the video id out of a full post URL.
///
/// Only https URLs on tiktok.com hosts pass <see cref="TryParse"/>, which is also what keeps
/// the server's outbound requests (short-link redirects, oEmbed) pointed at TikTok and nowhere else.
/// Pure and static so the rules are testable without the network.
/// </summary>
public static partial class TikTokLinks
{
    public const string Provider = "tiktok";

    public const int MaxInputLength = 2000;

    [GeneratedRegex(@"https?://[^\s<>""']+", RegexOptions.IgnoreCase)]
    private static partial Regex UrlPattern();

    // /@user/video/123, /@user/photo/123, /video/123, /v/123.html, /embed/v2/123
    [GeneratedRegex(@"/(?:video|photo|v|embed(?:/v2)?)/(\d{6,30})(?:\.html)?(?:[/?#]|$)", RegexOptions.IgnoreCase)]
    private static partial Regex VideoIdPattern();

    /// <summary>The first TikTok URL in <paramref name="text"/>, if there is one.</summary>
    public static bool TryParse(string? text, out Uri uri)
    {
        uri = null!;
        if (string.IsNullOrWhiteSpace(text) || text.Length > MaxInputLength)
        {
            return false;
        }

        foreach (Match match in UrlPattern().Matches(text))
        {
            var candidate = match.Value.TrimEnd('.', ',', ')', '!', '?');
            if (Uri.TryCreate(candidate, UriKind.Absolute, out var parsed) && IsTikTokHost(parsed))
            {
                // Plain http is upgraded - TikTok serves everything over https.
                uri = new UriBuilder(parsed) { Scheme = Uri.UriSchemeHttps, Port = -1 }.Uri;
                return true;
            }
        }

        return false;
    }

    /// <summary>True for https?://tiktok.com and its subdomains (www., m., vm., vt.).</summary>
    public static bool IsTikTokHost(Uri uri) =>
        (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp)
        && (uri.Host.Equals("tiktok.com", StringComparison.OrdinalIgnoreCase)
            || uri.Host.EndsWith(".tiktok.com", StringComparison.OrdinalIgnoreCase));

    /// <summary>The video id in a full post URL; null for a short link that still needs resolving.</summary>
    public static string? VideoId(Uri uri)
    {
        var match = VideoIdPattern().Match(uri.AbsolutePath);
        return match.Success ? match.Groups[1].Value : null;
    }
}
