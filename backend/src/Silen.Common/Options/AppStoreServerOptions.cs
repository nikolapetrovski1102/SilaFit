namespace Silen.Common.Options;

/// <summary>
/// Bound from the "AppStoreServer" configuration section. Credentials for
/// calling Apple's App Store Server API (outbound, server-to-server) -
/// distinct from AppleAuthOptions, which is for verifying inbound Sign in
/// with Apple identity tokens.
/// </summary>
public sealed class AppStoreServerOptions
{
    public const string SectionName = "AppStoreServer";

    /// <summary>App Store Connect API key id (the .p8 file's name), used as the JWT "kid".</summary>
    public string KeyId { get; set; } = string.Empty;

    /// <summary>App Store Connect issuer id, used as the JWT "iss".</summary>
    public string IssuerId { get; set; } = string.Empty;

    /// <summary>App bundle id, used as the JWT "bid" and cross-checked against every transaction payload.</summary>
    public string BundleId { get; set; } = string.Empty;

    /// <summary>The .p8 private key's PEM contents (inline). Prefer the path below in files.</summary>
    public string PrivateKey { get; set; } = string.Empty;

    /// <summary>Path to the .p8 private key file.</summary>
    public string PrivateKeyPath { get; set; } = string.Empty;

    /// <summary>"Production" or "Sandbox" - selects which App Store Server API host to call.</summary>
    public string Environment { get; set; } = "Production";
}

/// <summary>Bound from the "GooglePlay" configuration section. Credentials for calling the
/// Play Developer API to verify/acknowledge subscription purchases.</summary>
public sealed class GooglePlayOptions
{
    public const string SectionName = "GooglePlay";

    /// <summary>Android applicationId, e.g. "com.nikolapetrovski.silafit".</summary>
    public string PackageName { get; set; } = string.Empty;

    /// <summary>Service-account JSON contents (inline). Prefer the path below in files.</summary>
    public string ServiceAccountJson { get; set; } = string.Empty;

    /// <summary>Path to a Play Developer API service-account JSON file.</summary>
    public string ServiceAccountJsonPath { get; set; } = string.Empty;
}
