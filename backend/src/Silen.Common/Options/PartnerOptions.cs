namespace Silen.Common.Options;

/// <summary>Bound from the "Partner" configuration section - the credentials the partner
/// website uses on /api/partner. Left empty in every committed appsettings file, which
/// keeps the endpoints shut (every call is refused) until all three secrets are set via
/// `dotnet user-secrets` or the container's env vars, same as Jwt:SigningKey.</summary>
public sealed class PartnerOptions
{
    public const string SectionName = "Partner";

    /// <summary>HTTP Basic username the partner sends.</summary>
    public string Username { get; set; } = string.Empty;

    /// <summary>HTTP Basic password the partner sends. Use a long random value, e.g. from `openssl rand -base64 32`.</summary>
    public string Password { get; set; } = string.Empty;

    /// <summary>Base64-encoded 32-byte (256-bit) AES key shared with the partner, used to
    /// encrypt the request payload end to end (see PartnerPayloadCipher). Deliberately a
    /// different key from Encryption:MasterKeyBase64, which never leaves this server.</summary>
    public string PayloadKeyBase64 { get; set; } = string.Empty;

    /// <summary>How far a payload's IssuedAtUtc may be from the server clock, either way,
    /// before it is refused - bounds how long a captured request could be replayed.</summary>
    public int MaxPayloadAgeSeconds { get; set; } = 300;
}
