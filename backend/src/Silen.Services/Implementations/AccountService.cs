using System.Text;
using System.Text.Json;
using Silen.Common.Contracts;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IAccountService"/>
public sealed class AccountService(IAccountProvider accountProvider, IEmailSender emailSender) : IAccountService
{
    private static readonly JsonSerializerOptions ExportJsonOptions = new() { WriteIndented = true };

    // "1 in 2 months" - the export emails a user's entire decrypted history as
    // a JSON attachment, so it's rate-limited far more tightly than an
    // ordinary resend/OTP cooldown to prevent it being used to exfiltrate
    // data or spam the mailbox.
    private const int ExportCooldownDays = 60;

    public Task<ServiceResult<bool>> DeleteAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await accountProvider.DeleteAsync(userId, cancellationToken);
            return true;
        });

    // Emails the export rather than returning it in the response - the payload
    // can include years of history, and this is a rare "download my data"
    // request, not a screen the app renders anything from.
    public Task<ServiceResult<AccountExportRequestResultModel>> ExportAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var eligibility = await accountProvider.TryBeginExportAsync(userId, ExportCooldownDays, cancellationToken);
            if (!eligibility.Allowed)
            {
                throw new ConflictException(
                    $"Account '{userId}' requested a data export before the cooldown elapsed.",
                    $"You can request a data export once every {ExportCooldownDays} days. Next available on {eligibility.NextAllowedAtUtc:yyyy-MM-dd}.");
            }

            var export = await accountProvider.ExportAsync(userId, cancellationToken);
            var email = export.Account.Email;
            if (string.IsNullOrWhiteSpace(email))
            {
                throw new ValidationException(
                    $"Account '{userId}' has no email on file for data export.",
                    "Add an email to your account before requesting a data export.");
            }

            var json = JsonSerializer.Serialize(export, ExportJsonOptions);
            var fileName = $"silafit-data-export-{DateTime.UtcNow:yyyy-MM-ddTHH-mm-ssZ}.json";
            var (subject, html) = AccountExportEmailTemplate.Build();

            await emailSender.SendWithAttachmentAsync(
                email, subject, html, fileName, Encoding.UTF8.GetBytes(json), "application/json", cancellationToken);

            return new AccountExportRequestResultModel { Email = email };
        });
}
