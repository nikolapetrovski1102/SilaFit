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

    /// <summary>Refresh-token exchange and sign-out, partitioned per client IP. Looser than
    /// <see cref="Auth"/>: a refresh token is 256 random bits, so there is nothing to guess,
    /// and many phones behind one gym or carrier IP all renew around the same time.</summary>
    public const string SessionRefresh = "session-refresh";

    /// <summary>Admin console sign-in, partitioned per client IP with a tighter window.</summary>
    public const string AdminAuth = "admin-auth";

    /// <summary>Billable AI analytics calls, partitioned per authenticated user (fallback IP).</summary>
    public const string Analytics = "analytics";

    /// <summary>Anonymous App Store / Play Store server notification callbacks, partitioned per client IP.</summary>
    public const string Webhooks = "webhooks";

    /// <summary>The website's anonymous support contact form, partitioned per client IP.</summary>
    public const string SupportContact = "support-contact";

    /// <summary>Nutrition-label photo reads - billable vision calls open to every tier -
    /// partitioned per authenticated user.</summary>
    public const string FoodLabelScan = "food-label-scan";

    /// <summary>Barcode lookups, partitioned per authenticated user. Loose: scanning a whole
    /// shopping bag is normal; this only stops a script from walking the barcode space
    /// through our server (and its catalog writes). Covers the lookup and the on-device
    /// Open Food Facts result post. The app holds itself to 15 OFF calls a minute.</summary>
    public const string BarcodeLookup = "barcode-lookup";

    /// <summary>Discount code redemption, partitioned per authenticated user (fallback IP) - tight enough to make guessing codes impractical.</summary>
    public const string PromoCodes = "promo-codes";

    /// <summary>The partner website's server-to-server lead endpoints, partitioned per client IP - also bounds Basic-auth guessing.</summary>
    public const string Partner = "partner";

    /// <summary>The website download page's anonymous visit beacon, partitioned per client IP - loose,
    /// since a whole gym can scan the same QR code on one Wi-Fi.</summary>
    public const string DownloadVisit = "download-visit";
}
