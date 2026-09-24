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

    // Below: the Sign in with Apple key (Certificates, Identifiers & Profiles >
    // Keys, with "Sign in with Apple" enabled) - a different key from the App
    // Store Server API one. Used to exchange the login's authorization code for
    // a refresh token and to revoke it when the account is deleted. Leaving
    // these empty only disables token revocation; sign-in still works.

    /// <summary>Apple Developer Team id, used as the client secret's "iss".</summary>
    public string TeamId { get; set; } = string.Empty;

    /// <summary>The Sign in with Apple key's id, used as the client secret's "kid".</summary>
    public string KeyId { get; set; } = string.Empty;

    /// <summary>The .p8 private key's PEM contents (inline). Prefer the path below in files.</summary>
    public string PrivateKey { get; set; } = string.Empty;

    /// <summary>Path to the .p8 private key file.</summary>
    public string PrivateKeyPath { get; set; } = string.Empty;
}
