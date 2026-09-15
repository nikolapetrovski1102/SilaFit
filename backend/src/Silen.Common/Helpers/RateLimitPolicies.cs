namespace Silen.Common.Helpers;

/// <summary>
/// Names of the named rate-limit policies registered in the API's Program.cs.
/// Kept here so controller attributes and the registration share one source of
/// truth rather than duplicating magic strings.
/// </summary>
public static class RateLimitPolicies
{
    /// <summary>Anonymous auth endpoints (device/register/login/resend), partitioned per client IP.</summary>
    public const string Auth = "auth";

    /// <summary>Admin console sign-in, partitioned per client IP with a tighter window.</summary>
    public const string AdminAuth = "admin-auth";

    /// <summary>Billable AI analytics calls, partitioned per authenticated user (fallback IP).</summary>
    public const string Analytics = "analytics";
}
