using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Silen.Common.Helpers;
using Silen.Common.Options;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Api.Controllers;

/// <summary>The app's side of trainer documents: which ones the user holds for a program, and opening one.</summary>
[ApiController]
[Route("api/documents")]
[Authorize]
public sealed class TrainerDocumentsController(
    ITrainerDocumentService documentService,
    ILogger<TrainerDocumentsController> logger) : ControllerBase
{
    /// <summary>Documents the caller holds for one split (<c>kind=Split</c>) or diet plan (<c>kind=DietPlan</c>).</summary>
    [HttpGet]
    public async Task<IActionResult> GetMine([FromQuery] string kind, [FromQuery] Guid targetId, CancellationToken cancellationToken) =>
        (await documentService.GetForUserAsync(User.GetUserId(), kind, targetId, cancellationToken)).ToActionResult(logger);

    /// <summary>A short-lived viewer URL for the app's secure WebView.</summary>
    [HttpPost("{grantId:guid}/open")]
    public async Task<IActionResult> Open(Guid grantId, CancellationToken cancellationToken) =>
        (await documentService.OpenAsync(User.GetUserId(), grantId, cancellationToken)).ToActionResult(logger);
}

/// <summary>
/// The viewer itself. Anonymous at the HTTP level on purpose: the app's WebView
/// carries no bearer token, so access is decided by the service from either a
/// ticket (<c>?t=</c>) the app just minted, or the console's session cookie.
/// Anything else gets a page that reveals nothing about the document.
/// </summary>
[ApiController]
[Route("api/documents")]
[AllowAnonymous]
public sealed class DocumentViewerController(
    ITrainerDocumentService documentService,
    IOptions<AdminAuthOptions> adminAuthOptions,
    ILogger<DocumentViewerController> logger) : ControllerBase
{
    private string? AdminSessionToken => AdminSessionCookie.Read(Request, adminAuthOptions.Value);

    [HttpGet("view/{token}")]
    public async Task<IActionResult> ViewGrant(string token, [FromQuery] string? t, CancellationToken cancellationToken)
    {
        var view = await documentService.ResolveGrantViewAsync(token, t, AdminSessionToken, cancellationToken);
        if (!view.Allowed)
        {
            return Page(TrainerDocumentViewerPage.RenderLocked(), StatusCodes.Status403Forbidden);
        }

        if (view.GrantId is { } grantId)
        {
            try
            {
                await documentService.RecordOpenAsync(grantId, cancellationToken);
            }
            catch (Exception exception)
            {
                // Counting opens is bookkeeping; it must never stop the client reading.
                logger.LogWarning(exception, "Could not record a trainer document open for grant {GrantId}.", grantId);
            }
        }

        var fileUrl = $"{Uri.EscapeDataString(token)}/file" + (string.IsNullOrEmpty(t) || view.IsPreview ? "" : $"?t={Uri.EscapeDataString(t)}");
        return Page(TrainerDocumentViewerPage.Render(view.Title, view.Watermark, view.TrainerUsername, view.IsPreview, fileUrl), 200);
    }

    [HttpGet("view/{token}/file")]
    public async Task<IActionResult> GrantFile(string token, [FromQuery] string? t, CancellationToken cancellationToken) =>
        File(await documentService.ResolveGrantViewAsync(token, t, AdminSessionToken, cancellationToken));

    /// <summary>The console's preview of a document (admin cookie only).</summary>
    [HttpGet("preview/{documentId:guid}")]
    public async Task<IActionResult> Preview(Guid documentId, CancellationToken cancellationToken)
    {
        var view = await documentService.ResolvePreviewAsync(documentId, AdminSessionToken, cancellationToken);
        return view.Allowed
            ? Page(TrainerDocumentViewerPage.Render(view.Title, view.Watermark, null, true, $"{documentId}/file"), 200)
            : Page(TrainerDocumentViewerPage.RenderLocked(), StatusCodes.Status403Forbidden);
    }

    [HttpGet("preview/{documentId:guid}/file")]
    public async Task<IActionResult> PreviewFile(Guid documentId, CancellationToken cancellationToken) =>
        File(await documentService.ResolvePreviewAsync(documentId, AdminSessionToken, cancellationToken));

    private ContentResult Page(string html, int statusCode)
    {
        NoStore();
        Response.Headers.ContentSecurityPolicy = TrainerDocumentViewerPage.ContentSecurityPolicy;
        return new ContentResult { Content = html, ContentType = "text/html; charset=utf-8", StatusCode = statusCode };
    }

    private IActionResult File(TrainerDocumentViewModel view)
    {
        if (!view.Allowed || view.FilePath is null || !System.IO.File.Exists(view.FilePath))
        {
            return NotFound();
        }

        NoStore();
        // Inline only for the viewer's fetch; no filename so a browser that lands
        // here directly doesn't get a ready-named download.
        Response.Headers.ContentDisposition = "inline";
        return PhysicalFile(view.FilePath, "application/pdf", enableRangeProcessing: true);
    }

    private void NoStore()
    {
        Response.Headers.CacheControl = "no-store, max-age=0";
        Response.Headers.Pragma = "no-cache";
        Response.Headers["X-Robots-Tag"] = "noindex, nofollow";
    }
}
