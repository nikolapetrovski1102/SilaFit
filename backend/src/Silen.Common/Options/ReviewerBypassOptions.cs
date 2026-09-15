namespace Silen.Common.Options;

/// <summary>Bound from the "ReviewerBypass" configuration section. When both values are set,
/// registering with <see cref="Email"/> gets a fixed verification code instead of a random,
/// emailed one - so App Store / Play Store reviewers can create and sign back into the
/// demo account without inbox access. Left empty in every committed appsettings file; set
/// via `dotnet user-secrets` for local `dotnet run` or the container's env vars, same as
/// Jwt:SigningKey and OpenRouter:ApiKey. Leave empty outside of an active review to disable.</summary>
public sealed class ReviewerBypassOptions
{
    public const string SectionName = "ReviewerBypass";

    public string Email { get; set; } = string.Empty;

    public string Code { get; set; } = string.Empty;
}
