namespace Silen.Services.Implementations;

/// <summary>
/// Builds the subject/HTML body for the "confirm your email" message sent the
/// moment a new console operator is created. Link-based rather than a typed code
/// like <see cref="VerificationEmailTemplate"/>/<see cref="AdminEmailOtpTemplate"/>
/// - there is no app or console session open yet for the recipient to type a code
/// into, so a one-click link is the only step that makes sense here.
/// </summary>
public static class OperatorEmailConfirmTemplate
{
    public static (string Subject, string Html) Build(string username, string confirmUrl) =>
    (
        "Confirm your SilaFit admin email",
        $"""
        <div style="font-family:-apple-system,'Segoe UI',Roboto,sans-serif;max-width:420px;margin:0 auto;padding:32px 24px;">
          <p style="font-size:15px;color:#241B12;">A SilaFit admin console account was just created for <strong>{username}</strong> with this address on file.</p>
          <p style="font-size:15px;color:#241B12;">Confirm it to enable "send email code instead" as a sign-in second factor:</p>
          <p style="text-align:center;margin:28px 0;">
            <a href="{confirmUrl}" style="display:inline-block;background:#800020;color:#fff;font-weight:600;font-size:15px;text-decoration:none;padding:12px 28px;border-radius:8px;">Confirm email</a>
          </p>
          <p style="font-size:13px;color:#6E624A;">This link expires in 48 hours. If you didn't expect this, ignore it - the address stays unconfirmed and the account still needs its authenticator app for sign-in.</p>
        </div>
        """
    );
}
