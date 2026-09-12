namespace Silen.Common.Options;

/// <summary>Bound from the "Encryption" configuration section - the master key for
/// Silen.Common.Helpers.FieldCipher's AES-256-GCM field-level encryption of sensitive
/// columns (bodyweight, height/age/gender/goal, meal titles/macros, nutrition
/// targets). Left empty in every committed appsettings file - set via
/// `dotnet user-secrets` for local `dotnet run` or the container's env vars, same as
/// Jwt:SigningKey and OpenRouter:ApiKey.</summary>
public sealed class EncryptionOptions
{
    public const string SectionName = "Encryption";

    /// <summary>Base64-encoded 32-byte (256-bit) AES key, e.g. from `openssl rand -base64 32`.</summary>
    public string MasterKeyBase64 { get; set; } = string.Empty;
}
