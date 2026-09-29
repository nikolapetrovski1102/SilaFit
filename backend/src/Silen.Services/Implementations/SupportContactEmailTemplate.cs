using System.Net;

namespace Silen.Services.Implementations;

/// <summary>
/// Builds the subject/HTML body of a website support-form message as it lands in
/// the support inbox (see SupportService). Every visitor-supplied value is
/// HTML-encoded - this is an anonymous form, so the body is untrusted input.
/// </summary>
public static class SupportContactEmailTemplate
{
    public static (string Subject, string Html) Build(string name, string email, string topic, string message)
    {
        // CR/LF stripped so a crafted name can't break out of the Subject header.
        var subjectName = name.Replace("\r", " ").Replace("\n", " ");
        var body = WebUtility.HtmlEncode(message).Replace("\r\n", "\n").Replace("\n", "<br>");

        return (
            $"[Support] {topic} - {subjectName}",
            $"""
            <div style="font-family:-apple-system,'Segoe UI',Roboto,sans-serif;max-width:560px;margin:0 auto;padding:32px 24px;">
              <p style="font-size:13px;color:#6E624A;margin:0 0 4px;">Sent from the support form on sila.fitness</p>
              <p style="font-size:15px;color:#241B12;margin:0 0 20px;"><strong>{WebUtility.HtmlEncode(name)}</strong> &lt;{WebUtility.HtmlEncode(email)}&gt; &middot; {WebUtility.HtmlEncode(topic)}</p>
              <div style="font-size:15px;line-height:1.6;color:#241B12;border-top:1px solid #E5DCC5;padding-top:20px;">{body}</div>
              <p style="font-size:13px;color:#6E624A;margin-top:24px;">Reply to this email to answer the sender directly.</p>
            </div>
            """
        );
    }
}
