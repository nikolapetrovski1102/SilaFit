using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Options;
using MimeKit;
using Silen.Common.Options;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IEmailSender"/>
public sealed class SmtpEmailSender(IOptions<SmtpOptions> options) : IEmailSender
{
    public Task SendAsync(string toEmail, string subject, string htmlBody, CancellationToken cancellationToken = default) =>
        SendMessageAsync(toEmail, subject, new BodyBuilder { HtmlBody = htmlBody }, cancellationToken);

    public Task SendWithAttachmentAsync(
        string toEmail,
        string subject,
        string htmlBody,
        string attachmentFileName,
        byte[] attachmentContent,
        string attachmentContentType,
        CancellationToken cancellationToken = default)
    {
        var builder = new BodyBuilder { HtmlBody = htmlBody };
        builder.Attachments.Add(attachmentFileName, attachmentContent, ContentType.Parse(attachmentContentType));
        return SendMessageAsync(toEmail, subject, builder, cancellationToken);
    }

    private async Task SendMessageAsync(string toEmail, string subject, BodyBuilder bodyBuilder, CancellationToken cancellationToken)
    {
        var settings = options.Value;

        var message = new MimeMessage();
        message.From.Add(new MailboxAddress(settings.FromName, settings.FromAddress));
        message.To.Add(MailboxAddress.Parse(toEmail));
        message.Subject = subject;
        message.Body = bodyBuilder.ToMessageBody();

        using var client = new SmtpClient();
        await client.ConnectAsync(settings.Host, settings.Port, SecureSocketOptions.StartTls, cancellationToken).ConfigureAwait(false);
        await client.AuthenticateAsync(settings.Username, settings.Password, cancellationToken).ConfigureAwait(false);
        await client.SendAsync(message, cancellationToken).ConfigureAwait(false);
        await client.DisconnectAsync(true, cancellationToken).ConfigureAwait(false);
    }
}
