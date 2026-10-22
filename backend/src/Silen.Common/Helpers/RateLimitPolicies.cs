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

    /// <summary>Anonymous App Store / Play Store server notification callbacks, partitioned per client IP.</summary>
    public const string Webhooks = "webhooks";

    /// <summary>The website's anonymous support contact form, partitioned per client IP.</summary>
    public const string SupportContact = "support-contact";

    /// <summary>Discount code redemption, partitioned per authenticated user (fallback IP) - tight enough to make guessing codes impractical.</summary>
    public const string PromoCodes = "promo-codes";

    /// <summary>The partner website's server-to-server lead endpoints, partitioned per client IP - also bounds Basic-auth guessing.</summary>
    public const string Partner = "partner";
}
