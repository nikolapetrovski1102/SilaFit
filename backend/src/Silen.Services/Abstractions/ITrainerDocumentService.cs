using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>A document upload as plain BCL types (the controller reads the multipart form).</summary>
/// <param name="TargetId">The split / plan to attach to. Null with <paramref name="Generate"/> creates a new one from the document.</param>
public sealed record TrainerDocumentUploadRequest(
    string Kind, Guid? TargetId, string? Title, bool Generate, Stream Content, string FileName, long LengthBytes);

/// <summary>What the secure viewer may show for one request. When <see cref="Allowed"/> is false the
/// page tells the visitor to open the document in the app instead.</summary>
public sealed class TrainerDocumentViewModel
{
    public bool Allowed { get; init; }
    public string Title { get; init; } = string.Empty;

    /// <summary>Burned into every rendered page: whose copy this is.</summary>
    public string Watermark { get; init; } = string.Empty;

    public string? TrainerUsername { get; init; }

    /// <summary>True for a trainer looking at the file from the console.</summary>
    public bool IsPreview { get; init; }

    /// <summary>Absolute path of the stored PDF. Never sent to a client.</summary>
    public string? FilePath { get; init; }

    public Guid? GrantId { get; init; }
}

public interface ITrainerDocumentService
{
    /* ---- console ---- */

    Task<ServiceResult<List<TrainerDocumentModel>>> GetForTargetAsync(
        string? sessionToken, string kind, Guid targetId, CancellationToken cancellationToken = default);

    Task<ServiceResult<TrainerDocumentUploadResultDto>> UploadAsync(
        string? sessionToken, TrainerDocumentUploadRequest request, string? clientIp, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> DeleteAsync(
        string? sessionToken, Guid documentId, string? clientIp, CancellationToken cancellationToken = default);

    Task<ServiceResult<List<TrainerDocumentGrantModel>>> GetGrantsAsync(
        string? sessionToken, Guid documentId, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> AssignAsync(
        string? sessionToken, AdminTrainerDocumentGrantRequest request, string? clientIp, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> RevokeAsync(
        string? sessionToken, Guid documentId, Guid grantId, string? clientIp, CancellationToken cancellationToken = default);

    /* ---- app ---- */

    Task<ServiceResult<List<UserTrainerDocumentModel>>> GetForUserAsync(
        Guid userId, string kind, Guid targetId, CancellationToken cancellationToken = default);

    /// <summary>Mints a short-lived ticket on the caller's own grant and returns the viewer URL carrying it.</summary>
    Task<ServiceResult<TrainerDocumentOpenResultDto>> OpenAsync(
        Guid userId, Guid grantId, CancellationToken cancellationToken = default);

    /* ---- viewer ---- */

    /// <summary>A client's link: renders for a valid app ticket, or for a console session allowed to manage the document.</summary>
    Task<TrainerDocumentViewModel> ResolveGrantViewAsync(
        string token, string? ticket, string? adminSessionToken, CancellationToken cancellationToken = default);

    /// <summary>The console's own preview of a document, before or regardless of any grant.</summary>
    Task<TrainerDocumentViewModel> ResolvePreviewAsync(
        Guid documentId, string? adminSessionToken, CancellationToken cancellationToken = default);

    Task RecordOpenAsync(Guid grantId, CancellationToken cancellationToken = default);
}
