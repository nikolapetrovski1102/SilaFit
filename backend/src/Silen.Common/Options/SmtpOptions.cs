namespace Silen.Common.Options;

/// <summary>Bound from the "Smtp" configuration section - the mailbox that sends the
/// email-registration verification code (see SmtpEmailSender). Left empty in every
/// committed appsettings file - set via `dotnet user-secrets` for local `dotnet run`
/// or the container's env vars, same as Jwt:SigningKey and OpenRouter:ApiKey.</summary>
public sealed class SmtpOptions
{
    public const string SectionName = "Smtp";

    public string Host { get; set; } = string.Empty;

    public int Port { get; set; } = 587;

    public string Username { get; set; } = string.Empty;

    public string Password { get; set; } = string.Empty;

    public string FromAddress { get; set; } = string.Empty;

    public string FromName { get; set; } = "SilaFit";
}
