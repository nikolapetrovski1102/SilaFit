namespace Silen.Common.Options;

/// <summary>
/// Bound from the "AdminAuth" configuration section. Console-operator auth is
/// intentionally separate from the app's JWT flow: the app authenticates with a
/// bearer token it holds in memory, while the admin dashboard is gated by an
/// HttpOnly cookie that nginx validates before it will serve admin.html at all
/// (see deploy/nginx-sila.fitness.conf).
/// </summary>
public sealed class AdminAuthOptions
{
    public const string SectionName = "AdminAuth";

    /// <summary>Cookie the console session token is carried in. Must match the nginx name in deploy/.</summary>
    public string CookieName { get; set; } = "silafit_admin_session";

    /// <summary>
    /// False only for local development over plain http, where a Secure cookie
    /// would never be sent back. Always true in production.
    /// </summary>
    public bool CookieSecure { get; set; } = true;

    /// <summary>Wrong password + wrong code attempts allowed before the account locks.</summary>
    public int LockoutThreshold { get; set; } = 5;

    public int LockoutMinutes { get; set; } = 15;

    /// <summary>How long the password step's challenge token stays usable while the user reaches for their phone.</summary>
    public int ChallengeMinutes { get; set; } = 5;

    /// <summary>Idle timeout: the session dies after this long without a single authenticated request.</summary>
    public int SessionIdleMinutes { get; set; } = 30;

    /// <summary>Hard ceiling on a session's life, no matter how active it is.</summary>
    public int SessionAbsoluteMinutes { get; set; } = 480;

    /// <summary>Label shown next to the account in the authenticator app.</summary>
    public string TotpIssuer { get; set; } = "SilaFit Admin";

    /// <summary>Digits in the authenticator code. 6 is what every authenticator app assumes.</summary>
    public int TotpDigits { get; set; } = 6;

    /// <summary>Seconds per code. 30 is the RFC 6238 default; accept only RFC 6238 values.</summary>
    public int TotpStepSeconds { get; set; } = 30;

    /// <summary>Steps of clock drift tolerated on either side (1 = the previous + next code also work).</summary>
    public int TotpWindowSteps { get; set; } = 1;

    /// <summary>Origin the operator-creation confirmation email's link is built against. No trailing slash.</summary>
    public string ConsoleBaseUrl { get; set; } = "https://admin.sila.fitness";

    /// <summary>How long an operator's email-confirmation link stays clickable.</summary>
    public int EmailConfirmHours { get; set; } = 48;
}
