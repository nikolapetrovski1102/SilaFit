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
