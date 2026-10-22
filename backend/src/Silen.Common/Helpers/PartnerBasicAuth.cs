using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using Silen.Common.Options;

namespace Silen.Common.Helpers;

/// <summary>
/// Checks an HTTP Basic Authorization header against the configured partner credentials.
/// Both halves are compared as SHA-256 digests with a fixed-time comparison, and both are
/// always compared, so response timing says nothing about which half (or how much of it)
/// was right. Unconfigured credentials never match, which keeps the partner endpoints
/// shut by default.
/// </summary>
public static class PartnerBasicAuth
{
    public const string Challenge = "Basic realm=\"SilaFit Partner\", charset=\"UTF-8\"";

    public static bool IsAuthorized(string? authorizationHeader, PartnerOptions options)
    {
        if (string.IsNullOrEmpty(options.Username) || string.IsNullOrEmpty(options.Password))
        {
            return false;
        }

        if (!AuthenticationHeaderValue.TryParse(authorizationHeader, out var header)
            || !string.Equals(header.Scheme, "Basic", StringComparison.OrdinalIgnoreCase)
            || string.IsNullOrEmpty(header.Parameter))
        {
            return false;
        }

        string credentials;
        try
        {
            credentials = Encoding.UTF8.GetString(Convert.FromBase64String(header.Parameter));
        }
        catch (FormatException)
        {
            return false;
        }

        // The username may not contain ':' (RFC 7617); the password may.
        var separator = credentials.IndexOf(':');
        if (separator < 0)
        {
            return false;
        }

        var usernameMatches = FixedTimeEquals(credentials[..separator], options.Username);
        var passwordMatches = FixedTimeEquals(credentials[(separator + 1)..], options.Password);
        return usernameMatches & passwordMatches;
    }

    private static bool FixedTimeEquals(string supplied, string expected) =>
        CryptographicOperations.FixedTimeEquals(
            SHA256.HashData(Encoding.UTF8.GetBytes(supplied)),
            SHA256.HashData(Encoding.UTF8.GetBytes(expected)));
}
