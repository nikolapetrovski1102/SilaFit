using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Common.Options;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>
/// Trainer documents and partner providers in the console. Same cookie-based
/// shape as <see cref="AdminContentController"/>: the service enforces the
/// content.* permission (and program ownership) for every call.
/// </summary>
[ApiController]
[Route("api/admin")]
public sealed class AdminDocumentsController(
    ITrainerDocumentService documentService,
    ISupplementProviderService providerService,
    IOptions<AdminAuthOptions> adminAuthOptions,
    ILogger<AdminDocumentsController> logger) : ControllerBase
{
    private string? SessionToken => AdminSessionCookie.Read(Request, adminAuthOptions.Value);

    private string? ClientIp => HttpContext.Connection.RemoteIpAddress?.ToString();

    /* ------------------------------- documents ------------------------------- */

    [HttpGet("documents")]
    public async Task<IActionResult> GetForTarget([FromQuery] string kind, [FromQuery] Guid targetId, CancellationToken cancellationToken) =>
        (await documentService.GetForTargetAsync(SessionToken, kind, targetId, cancellationToken)).ToActionResult(logger);

    /// <summary>Multipart: file (.pdf/.docx/.doc), kind, targetId (optional), title (optional), generate (bool).
    /// Without targetId and with generate, AI builds a new private program from the document.</summary>
    [HttpPost("documents")]
    [RequestSizeLimit(25 * 1024 * 1024)]
    [RequestFormLimits(MultipartBodyLengthLimit = 25 * 1024 * 1024)]
    public async Task<IActionResult> Upload(
        IFormFile? file,
        [FromForm] string kind,
        [FromForm] Guid? targetId,
        [FromForm] string? title,
        [FromForm] bool generate,
        CancellationToken cancellationToken)
    {
        if (file is null || file.Length == 0)
        {
            return BadRequest(ApiResponse.Fail("Choose a PDF or Word document to upload."));
        }

        await using var stream = file.OpenReadStream();
        var request = new TrainerDocumentUploadRequest(kind, targetId, title, generate, stream, file.FileName, file.Length);
        return (await documentService.UploadAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);
    }

    [HttpDelete("documents/{documentId:guid}")]
    public async Task<IActionResult> Delete(Guid documentId, CancellationToken cancellationToken) =>
        (await documentService.DeleteAsync(SessionToken, documentId, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpGet("documents/{documentId:guid}/grants")]
    public async Task<IActionResult> GetGrants(Guid documentId, CancellationToken cancellationToken) =>
        (await documentService.GetGrantsAsync(SessionToken, documentId, cancellationToken)).ToActionResult(logger);

    [HttpPost("documents/{documentId:guid}/grants")]
    public async Task<IActionResult> Assign(Guid documentId, [FromBody] AdminTrainerDocumentGrantRequest request, CancellationToken cancellationToken)
    {
        request.DocumentId = documentId;
        return (await documentService.AssignAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);
    }

    [HttpDelete("documents/{documentId:guid}/grants/{grantId:guid}")]
    public async Task<IActionResult> Revoke(Guid documentId, Guid grantId, CancellationToken cancellationToken) =>
        (await documentService.RevokeAsync(SessionToken, documentId, grantId, ClientIp, cancellationToken)).ToActionResult(logger);

    /* ------------------------------- providers ------------------------------- */

    [HttpGet("providers")]
    public async Task<IActionResult> GetProviders(CancellationToken cancellationToken) =>
        (await providerService.GetAllAsync(SessionToken, cancellationToken)).ToActionResult(logger);

    [HttpPost("providers")]
    public async Task<IActionResult> SaveProvider([FromBody] AdminSupplementProviderUpsertRequest request, CancellationToken cancellationToken) =>
        (await providerService.SaveAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpDelete("providers/{providerId:guid}")]
    public async Task<IActionResult> DeleteProvider(Guid providerId, CancellationToken cancellationToken) =>
        (await providerService.DeleteAsync(SessionToken, providerId, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpPost("providers/logo")]
    [RequestSizeLimit(10 * 1024 * 1024)]
    public async Task<IActionResult> UploadLogo(IFormFile? file, CancellationToken cancellationToken)
    {
        if (file is null || file.Length == 0)
        {
            return BadRequest(ApiResponse.Fail("Choose an image to upload."));
        }

        await using var stream = file.OpenReadStream();
        var upload = new ImageUploadRequest(stream, file.FileName, file.ContentType, file.Length);
        return (await providerService.UploadLogoAsync(SessionToken, upload, ClientIp, cancellationToken)).ToActionResult(logger);
    }
}
