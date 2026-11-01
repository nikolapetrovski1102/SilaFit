namespace Silen.Common.Options;

/// <summary>Bound from the "Jwt" configuration section.</summary>
public sealed class JwtOptions
{
    public const string SectionName = "Jwt";

    public string Issuer { get; set; } = string.Empty;

    public string Audience { get; set; } = string.Empty;

    public string SigningKey { get; set; } = string.Empty;

    public int ExpiryMinutes { get; set; } = 60 * 24 * 30;

    /// <summary>How long a refresh token stays valid without being used. Slides
    /// forward on every use, so an app opened at least this often never signs out.</summary>
    public int RefreshTokenDays { get; set; } = 180;
}
