namespace Silen.Services.Abstractions;

/// <summary>
/// Sends transactional email - today only the registration verification
/// code (see AuthService). Kept behind an interface, like
/// IGoogleTokenVerifier/IAppleTokenVerifier, so swapping the SMTP
/// implementation for a provider API never touches the caller.
/// </summary>
public interface IEmailSender
{
    Task SendAsync(string toEmail, string subject, string htmlBody, CancellationToken cancellationToken = default);
}
