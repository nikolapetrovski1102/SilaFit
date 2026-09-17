namespace Silen.Services.Implementations;

/// <summary>
/// Builds the subject/HTML body for the "download my data" export email -
/// the JSON payload itself goes as an attachment, this is just the covering
/// note (see AccountService.ExportAsync).
/// </summary>
public static class AccountExportEmailTemplate
{
    public static (string Subject, string Html) Build() =>
    (
        "Your SilaFit data export",
        """
        <div style="font-family:-apple-system,'Segoe UI',Roboto,sans-serif;max-width:420px;margin:0 auto;padding:32px 24px;">
          <p style="font-size:15px;color:#241B12;">Attached is a copy of all the data SilaFit holds for your account, as a JSON file.</p>
          <p style="font-size:13px;color:#6E624A;">If you didn't request this export, please contact support - someone may have accessed your account.</p>
        </div>
        """
    );
}
