namespace Silen.Common.Options;

/// <summary>Bound from the "GoogleAuth" configuration section.</summary>
public sealed class GoogleAuthOptions
{
    public const string SectionName = "GoogleAuth";

    /// <summary>OAuth client id(s) the app's Google Sign-In button(s) use - the token's "aud" must match one.</summary>
    public string[] ClientIds { get; set; } = [];
}

/// <summary>Bound from the "AppleAuth" configuration section.</summary>
public sealed class AppleAuthOptions
{
    public const string SectionName = "AppleAuth";

    /// <summary>App bundle id(s) - the identity token's "aud" must match one.</summary>
    public string[] ClientIds { get; set; } = [];
}
