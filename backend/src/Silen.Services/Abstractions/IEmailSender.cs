namespace Silen.Services.Abstractions;

/// <summary>
/// Sends transactional email - registration verification codes, monthly
/// reviews, and the "download my data" export. Kept behind an interface,
/// like IGoogleTokenVerifier/IAppleTokenVerifier, so swapping the SMTP
/// implementation for a provider API never touches the caller.
/// </summary>
public interface IEmailSender
{
    Task SendAsync(string toEmail, string subject, string htmlBody, CancellationToken cancellationToken = default);

    /// <summary>Same as <see cref="SendAsync"/> but with a single file attachment - used
    /// by the account data export, which emails the JSON payload rather than
    /// returning it in the response body.</summary>
    Task SendWithAttachmentAsync(
        string toEmail,
        string subject,
        string htmlBody,
        string attachmentFileName,
        byte[] attachmentContent,
        string attachmentContentType,
        CancellationToken cancellationToken = default);
}
