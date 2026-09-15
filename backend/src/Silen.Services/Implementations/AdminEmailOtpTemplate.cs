namespace Silen.Services.Implementations;

/// <summary>
/// Builds the subject/HTML body for the admin console's "send email code instead"
/// second factor. Separate from <see cref="VerificationEmailTemplate"/> (registration)
/// so the copy can call out that this is a console sign-in, not an app one.
/// </summary>
public static class AdminEmailOtpTemplate
{
    public static (string Subject, string Html) Build(string code) =>
    (
        "Your SilaFit admin sign-in code",
        $"""
        <div style="font-family:-apple-system,'Segoe UI',Roboto,sans-serif;max-width:420px;margin:0 auto;padding:32px 24px;">
          <p style="font-size:15px;color:#241B12;">Use this code to finish signing in to the SilaFit admin console:</p>
          <p style="font-size:32px;font-weight:700;letter-spacing:8px;text-align:center;color:#800020;margin:24px 0;">{code}</p>
          <p style="font-size:13px;color:#6E624A;">This code expires in 10 minutes. If you didn't request this, someone may have your admin password - consider rotating it.</p>
        </div>
        """
    );
}
