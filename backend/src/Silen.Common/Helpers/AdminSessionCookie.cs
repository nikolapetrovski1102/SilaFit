using Microsoft.AspNetCore.Http;
using Silen.Common.Options;

namespace Silen.Common.Helpers;

/// <summary>
/// Outside helper that owns every detail of the console session cookie, so the
/// controller that issues it has no private methods (see the architecture notes:
/// controllers stay thin).
///
/// The cookie is HttpOnly (page scripts can never read the token), SameSite=Strict
/// (a cross-site form post can't ride an existing session) and Secure everywhere
/// except an explicit local-development override, since a Secure cookie is not sent
/// back over plain http.
/// </summary>
public static class AdminSessionCookie
{
    /// <summary>Response header carrying the signed-in operator's name - used by nginx logs and curl debugging.</summary>
    public const string UsernameHeaderName = "X-Admin-Username";

    public static string? Read(HttpRequest request, AdminAuthOptions options) =>
        request.Cookies.TryGetValue(options.CookieName, out var token) ? token : null;

    public static void Write(HttpResponse response, AdminAuthOptions options, string token, DateTime expiresAtUtc) =>
        response.Cookies.Append(options.CookieName, token, BuildOptions(options, new DateTimeOffset(expiresAtUtc, TimeSpan.Zero)));

    public static void Clear(HttpResponse response, AdminAuthOptions options) =>
        response.Cookies.Delete(options.CookieName, BuildOptions(options, null));

    private static CookieOptions BuildOptions(AdminAuthOptions options, DateTimeOffset? expires) => new()
    {
        HttpOnly = true,
        Secure = options.CookieSecure,
        SameSite = SameSiteMode.Strict,
        Path = "/",
        Expires = expires,
        IsEssential = true
    };
}
