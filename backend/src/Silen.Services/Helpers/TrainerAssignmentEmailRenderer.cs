using System.Net;
using System.Text;

namespace Silen.Services.Helpers;

/// <summary>One program PDF in the email, with the client's personal secure link.</summary>
public sealed record TrainerAssignmentEmailDocument(string Title, string Url);

/// <summary>
/// The "your trainer assigned you a program" email. The PDF is never attached:
/// each document goes out as a personal link that expires, stops working once a
/// newer email is sent or the trainer takes the document back, and opens in the
/// watermarked viewer. All user- and trainer-authored text is HTML-encoded.
/// </summary>
public static class TrainerAssignmentEmailRenderer
{
    public static string BuildSubject(string kindLabel, string programName, string? trainerName, bool documentOnly) =>
        documentOnly
            ? $"{TrainerOrYour(trainerName)} shared a {kindLabel} document with you"
            : $"{TrainerOrYour(trainerName)} assigned you a new {kindLabel}: {programName}";

    /// <param name="kindLabel">"split" or "diet plan".</param>
    /// <param name="documentOnly">True when only a document was shared (the program was already assigned).</param>
    public static string BuildHtml(
        string? displayName,
        string kindLabel,
        string programName,
        string? trainerName,
        bool documentOnly,
        IReadOnlyList<TrainerAssignmentEmailDocument> documents,
        int linkLifetimeHours)
    {
        var name = string.IsNullOrWhiteSpace(displayName) ? "there" : displayName.Trim();
        var trainer = string.IsNullOrWhiteSpace(trainerName) ? "Your trainer" : trainerName.Trim();
        var body = new StringBuilder();

        body.Append("<div style=\"background:#F6F1EA;padding:32px 12px;\">")
            .Append("<div style=\"font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;max-width:560px;")
            .Append("margin:0 auto;background:#FFFFFF;border-radius:16px;overflow:hidden;color:#241B12;line-height:1.5;\">");

        body.Append("<div style=\"background:#800020;padding:24px 28px;\">")
            .Append("<p style=\"margin:0;font-size:12px;letter-spacing:2px;text-transform:uppercase;color:#F3D9DF;\">SilaFit</p>")
            .Append("<h1 style=\"margin:6px 0 0;font-size:22px;color:#FFFFFF;font-weight:700;\">")
            .Append(Encode(programName)).Append("</h1></div>");

        body.Append("<div style=\"padding:24px 28px 8px;\">");
        body.Append($"<p style=\"margin:0 0 12px;font-size:15px;\">Hi {Encode(name)},</p>");
        body.Append(documentOnly
            ? $"<p style=\"margin:0 0 16px;font-size:15px;\">{Encode(trainer)} shared a document for your {Encode(kindLabel)} " +
              $"<strong>{Encode(programName)}</strong>.</p>"
            : $"<p style=\"margin:0 0 16px;font-size:15px;\">{Encode(trainer)} assigned you a new {Encode(kindLabel)}, " +
              $"<strong>{Encode(programName)}</strong>. It's waiting for you in the SilaFit app.</p>");

        if (documents.Count > 0)
        {
            body.Append("<p style=\"margin:20px 0 10px;font-size:13px;letter-spacing:1px;text-transform:uppercase;color:#6E624A;\">")
                .Append(documents.Count == 1 ? "Your program document" : "Your program documents")
                .Append("</p>");

            foreach (var document in documents)
            {
                body.Append("<table role=\"presentation\" style=\"width:100%;border-collapse:collapse;margin:0 0 10px;")
                    .Append("border:1px solid #EADFD2;border-radius:12px;\"><tr>")
                    .Append("<td style=\"padding:14px 16px;font-size:15px;font-weight:600;\">")
                    .Append(Encode(document.Title)).Append("</td>")
                    .Append("<td style=\"padding:10px 14px;text-align:right;white-space:nowrap;\">")
                    .Append($"<a href=\"{Encode(document.Url)}\" style=\"display:inline-block;background:#800020;color:#FFFFFF;")
                    .Append("text-decoration:none;font-size:14px;font-weight:600;padding:10px 18px;border-radius:999px;\">Open PDF</a>")
                    .Append("</td></tr></table>");
            }

            body.Append("<p style=\"margin:14px 0 0;font-size:13px;color:#6E624A;\">")
                .Append($"These links are personal to you and work for {linkLifetimeHours} hours. Every page is marked with your name, ")
                .Append("so please don't forward them. After that, open the program in the app and tap the document icon.</p>");
        }

        body.Append("</div>");
        body.Append("<p style=\"margin:24px 28px 28px;font-size:12px;color:#9C8F7A;\">")
            .Append("You're getting this because a trainer on SilaFit works with your account. ")
            .Append("If you don't recognise this, contact support@sila.fitness.</p>");
        body.Append("</div></div>");

        return body.ToString();
    }

    private static string TrainerOrYour(string? trainerName) =>
        string.IsNullOrWhiteSpace(trainerName) ? "Your trainer" : trainerName.Trim();

    private static string Encode(string value) => WebUtility.HtmlEncode(value);
}
