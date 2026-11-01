using System.Net;

namespace Silen.Services.Helpers;

/// <summary>
/// HTML for the secure document viewer. The page carries no inline script (the
/// admin host's CSP forbids anything but same-origin files, and this keeps the API
/// host the same): viewer.js and the vendored pdf.js are served from
/// /api/static/document-viewer/, and everything the script needs rides on data-*
/// attributes, HTML-encoded here.
///
/// The PDF is drawn onto canvases with the watermark burned into each page, with
/// no text layer (nothing to select or copy) and print hidden. That cannot stop a
/// determined person with a second phone; the watermark naming whose copy it is,
/// plus the warning, is what makes forwarding it unattractive.
/// </summary>
public static class TrainerDocumentViewerPage
{
    public const string ContentSecurityPolicy =
        "default-src 'none'; script-src 'self'; worker-src 'self'; connect-src 'self'; "
        + "style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; "
        + "base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

    private const string Styles = """
        :root { color-scheme: dark; --bg: #0e0f12; --panel: #17191e; --text: #f2f3f5; --muted: #9aa0aa; --warn: #ffb547; }
        * { box-sizing: border-box; }
        html, body { margin: 0; background: var(--bg); color: var(--text);
          font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          -webkit-user-select: none; user-select: none; -webkit-touch-callout: none; }
        .bar { position: sticky; top: 0; z-index: 2; background: var(--panel); padding: 10px 16px;
          border-bottom: 1px solid #262931; }
        .bar h1 { font-size: 16px; margin: 0 0 2px; font-weight: 600; overflow-wrap: anywhere; }
        .bar p { margin: 0; color: var(--warn); font-size: 12.5px; }
        main { padding: 12px 8px 40px; display: flex; flex-direction: column; align-items: center; gap: 12px; }
        canvas { width: 100%; max-width: 900px; height: auto; background: #fff; border-radius: 4px;
          pointer-events: none; }
        .state { color: var(--muted); padding: 48px 24px; text-align: center; max-width: 420px; }
        .state h2 { color: var(--text); font-size: 18px; margin: 0 0 8px; }
        @media print { body { display: none !important; } }
        """;

    /// <summary>The viewer for an allowed request.</summary>
    /// <param name="fileUrl">Relative URL of the PDF (carrying the ticket when there is one).</param>
    public static string Render(string title, string watermark, string? trainerUsername, bool isPreview, string fileUrl)
    {
        var notice = isPreview
            ? "Trainer preview. Clients see their own name across every page."
            : $"Personal copy for {watermark.Split(" · ")[0]}"
              + (string.IsNullOrWhiteSpace(trainerUsername) ? "" : $" from {trainerUsername}")
              + ". Please don't share, screenshot or forward it - every page is marked with your name.";

        return $"""
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5">
            <meta name="robots" content="noindex, nofollow">
            <title>{Encode(title)}</title>
            <style>{Styles}</style>
            </head>
            <body>
            <div class="bar">
              <h1>{Encode(title)}</h1>
              <p>{Encode(notice)}</p>
            </div>
            <main id="pages" data-file="{Encode(fileUrl)}" data-watermark="{Encode(watermark)}"
                  data-worker="/api/static/document-viewer/pdf.worker.min.js">
              <div class="state" id="status">Loading document…</div>
            </main>
            <script src="/api/static/document-viewer/pdf.min.js"></script>
            <script src="/api/static/document-viewer/viewer.js"></script>
            </body>
            </html>
            """;
    }

    /// <summary>What a visitor without a valid ticket or console session sees: no title, no hint of the content.</summary>
    public static string RenderLocked() => $"""
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="robots" content="noindex, nofollow">
        <title>SilaFit document</title>
        <style>{Styles}</style>
        </head>
        <body>
        <main>
          <div class="state">
            <h2>Open this in the SilaFit app</h2>
            Trainer documents only open inside the app, for the client they were shared with.
            If this is yours, open the program in SilaFit and tap the document icon.
          </div>
        </main>
        </body>
        </html>
        """;

    private static string Encode(string value) => WebUtility.HtmlEncode(value);
}
