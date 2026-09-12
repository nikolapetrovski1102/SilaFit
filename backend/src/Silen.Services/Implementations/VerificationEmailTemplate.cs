namespace Silen.Services.Implementations;

/// <summary>
/// Builds the subject/HTML body for the registration verification email.
/// A plain static builder rather than a method on AuthService since both
/// its start and resend flows need the exact same template.
/// </summary>
public static class VerificationEmailTemplate
{
    public static (string Subject, string Html) Build(string code) =>
    (
        "Your SilaFit verification code",
        $"""
        <div style="font-family:-apple-system,'Segoe UI',Roboto,sans-serif;max-width:420px;margin:0 auto;padding:32px 24px;">
          <p style="font-size:15px;color:#241B12;">Use this code to finish creating your SilaFit account:</p>
          <p style="font-size:32px;font-weight:700;letter-spacing:8px;text-align:center;color:#800020;margin:24px 0;">{code}</p>
          <p style="font-size:13px;color:#6E624A;">This code expires in 10 minutes. If you didn't request this, you can safely ignore this email.</p>
        </div>
        """
    );
}
