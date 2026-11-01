using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Silen.Common.Authorization;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <summary>
/// Trainer documents end to end.
///
/// Access model: the per-client link (<c>/api/documents/view/{token}</c>) is an
/// identifier, not a key. It renders only for (a) a console session that may
/// manage the document, or (b) a ticket the app minted for the signed-in owner of
/// that grant a few minutes earlier. A forwarded link therefore opens nothing,
/// and the watermark on every page names whose copy it was.
/// </summary>
public sealed class TrainerDocumentService(
    IAdminProvider adminProvider,
    IAdminRbacProvider adminRbacProvider,
    ITrainerDocumentsProvider documentsProvider,
    IDocumentProcessor documentProcessor,
    ITrainerDocumentAiImporter aiImporter,
    ITrainerAssignmentNotifier assignmentNotifier,
    IOptions<TrainerDocumentOptions> options,
    TimeProvider timeProvider,
    ILogger<TrainerDocumentService> logger) : ITrainerDocumentService
{
    public const string KindSplit = "Split";
    public const string KindDietPlan = "DietPlan";

    private static readonly string[] AllowedExtensions = [".pdf", ".docx", ".doc"];

    /* ------------------------------- console -------------------------------- */

    public Task<ServiceResult<List<TrainerDocumentModel>>> GetForTargetAsync(
        string? sessionToken, string kind, Guid targetId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var canonicalKind = CanonicalKind(kind);
            await RequireForKindAsync(sessionToken, canonicalKind, AdminPermissions.SplitsRead, AdminPermissions.DietPlansRead, null, cancellationToken);
            return await documentsProvider.GetForTargetAsync(canonicalKind, targetId, cancellationToken);
        });

    public Task<ServiceResult<TrainerDocumentUploadResultDto>> UploadAsync(
        string? sessionToken, TrainerDocumentUploadRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var kind = CanonicalKind(request.Kind);
            var (actor, canManageAll) = await RequireForKindAsync(
                sessionToken, kind, AdminPermissions.SplitsWrite, AdminPermissions.DietPlansWrite, clientIp, cancellationToken);

            if (request.TargetId is null && !request.Generate)
            {
                throw new ValidationException("Document upload with neither a target nor AI generation.",
                    "Pick the program to attach the document to, or let AI build a new one from it.");
            }

            var extension = Path.GetExtension(request.FileName ?? string.Empty).ToLowerInvariant();
            if (!AllowedExtensions.Contains(extension))
            {
                throw new ValidationException($"Document upload with extension '{extension}'.", "Upload a PDF or Word (.docx, .doc) file.");
            }
            if (request.LengthBytes <= 0 || request.LengthBytes > options.Value.MaxFileSizeBytes)
            {
                throw new ValidationException($"Document upload of {request.LengthBytes} bytes.",
                    $"The file must be under {options.Value.MaxFileSizeBytes / (1024 * 1024)} MB.");
            }

            using var buffer = new MemoryStream();
            await request.Content.CopyToAsync(buffer, cancellationToken);
            if (buffer.Length > options.Value.MaxFileSizeBytes)
            {
                throw new ValidationException($"Document stream ran to {buffer.Length} bytes.",
                    $"The file must be under {options.Value.MaxFileSizeBytes / (1024 * 1024)} MB.");
            }

            var pdf = await documentProcessor.NormalizeToPdfAsync(buffer.ToArray(), extension, cancellationToken);
            var title = DocumentTitle(request.Title, request.FileName!);

            var result = new TrainerDocumentUploadResultDto { Kind = kind };
            Guid targetId;
            if (request.TargetId is { } existing)
            {
                targetId = existing;
            }
            else
            {
                var text = documentProcessor.ExtractText(pdf, options.Value.MaxPromptCharacters);
                if (string.IsNullOrWhiteSpace(text) || text.Trim().Length < 40)
                {
                    throw new ValidationException("AI import on a document with no text layer.",
                        "This document has no readable text (it may be a scan). Attach it to an existing program without AI instead.");
                }

                var program = kind == KindSplit
                    ? await aiImporter.ReadSplitAsync(text, title, cancellationToken)
                    : await aiImporter.ReadDietPlanAsync(text, title, cancellationToken);

                var imported = kind == KindSplit
                    ? await documentsProvider.ImportSplitAsync(program.Name, program.Level, program.Description,
                        program.DurationDays, program.DaysJson, actor, cancellationToken)
                    : await documentsProvider.ImportDietPlanAsync(program.Name, program.Description,
                        program.DurationDays, program.DaysJson, actor, cancellationToken);

                var created = AdminMutationOutcomeMapper.Resolve(imported, "Imported.");
                targetId = created.Id ?? throw new ConflictException("Import procedure returned no id.", "AI import failed. Try again.");

                result.Generated = true;
                result.GeneratedName = program.Name;
                result.GeneratedDays = program.DayCount;
                result.GeneratedWeeks = program.DurationDays / 7;
            }

            var storedFileName = $"{Guid.NewGuid():N}.pdf";
            var storageDirectory = StorageDirectory();
            Directory.CreateDirectory(storageDirectory);
            var path = Path.Combine(storageDirectory, storedFileName);
            await File.WriteAllBytesAsync(path, pdf, cancellationToken);

            AdminMutationResultModel mutation;
            try
            {
                mutation = await documentsProvider.CreateAsync(
                    kind, targetId, title, OriginalName(request.FileName!), storedFileName, pdf.LongLength,
                    canManageAll, actor, cancellationToken);
            }
            catch
            {
                TryDelete(path);
                throw;
            }

            if (mutation.Result != AdminWriteOutcome.Success)
            {
                TryDelete(path);
            }
            var written = AdminMutationOutcomeMapper.Resolve(mutation, "Document attached.");

            result.DocumentId = written.Id ?? Guid.Empty;
            result.TargetId = targetId;
            result.Message = result.Generated
                ? $"Created '{result.GeneratedName}' ({result.GeneratedWeeks} week{(result.GeneratedWeeks == 1 ? "" : "s")}) from the document. Review it before assigning."
                : "Document attached.";
            return result;
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteAsync(
        string? sessionToken, Guid documentId, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var document = await RequireDocumentAsync(documentId, cancellationToken);
            var (actor, canManageAll) = await RequireForKindAsync(
                sessionToken, document.Kind, AdminPermissions.SplitsWrite, AdminPermissions.DietPlansWrite, clientIp, cancellationToken);

            var mutation = await documentsProvider.DeleteAsync(documentId, canManageAll, actor, cancellationToken);
            var result = AdminMutationOutcomeMapper.Resolve(mutation, "Document deleted. Its client links stop working.");
            TryDelete(StoredPath(document.StoredFileName));
            return result;
        });

    public Task<ServiceResult<List<TrainerDocumentGrantModel>>> GetGrantsAsync(
        string? sessionToken, Guid documentId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var document = await RequireDocumentAsync(documentId, cancellationToken);
            await RequireForKindAsync(sessionToken, document.Kind, AdminPermissions.SplitsRead, AdminPermissions.DietPlansRead, null, cancellationToken);

            var grants = await documentsProvider.GetGrantsAsync(documentId, cancellationToken);
            foreach (var grant in grants)
            {
                grant.ViewerPath = ViewerPath(grant.Token);
            }
            return grants;
        });

    public Task<ServiceResult<AdminWriteResultDto>> AssignAsync(
        string? sessionToken, AdminTrainerDocumentGrantRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var document = await RequireDocumentAsync(request.DocumentId, cancellationToken);
            var (actor, canManageAll) = await RequireForKindAsync(
                sessionToken, document.Kind, AdminPermissions.SplitsAssign, AdminPermissions.DietPlansAssign, clientIp, cancellationToken);

            var mutation = await documentsProvider.AssignAsync(
                request.DocumentId, request.UserId, NewToken(), canManageAll, actor, cancellationToken);
            var result = AdminMutationOutcomeMapper.Resolve(mutation, "Document shared with the client.");

            // Push + email with a secure link. Best effort: the grant is already committed.
            await assignmentNotifier.NotifyDocumentSharedAsync(document, request.UserId, actor, cancellationToken);
            return result;
        });

    public Task<ServiceResult<AdminWriteResultDto>> RevokeAsync(
        string? sessionToken, Guid documentId, Guid grantId, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var document = await RequireDocumentAsync(documentId, cancellationToken);
            var (actor, canManageAll) = await RequireForKindAsync(
                sessionToken, document.Kind, AdminPermissions.SplitsAssign, AdminPermissions.DietPlansAssign, clientIp, cancellationToken);

            // The grant must belong to the document whose kind the permission check used.
            var grants = await documentsProvider.GetGrantsAsync(documentId, cancellationToken);
            if (grants.All(g => g.GrantId != grantId))
            {
                throw new NotFoundException($"Grant {grantId} is not on document {documentId}.", "That client no longer has this document.");
            }

            var mutation = await documentsProvider.RevokeAsync(grantId, canManageAll, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Access revoked. The client's link no longer opens.");
        });

    /* --------------------------------- app ---------------------------------- */

    public Task<ServiceResult<List<UserTrainerDocumentModel>>> GetForUserAsync(
        Guid userId, string kind, Guid targetId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
            await documentsProvider.GetForUserAsync(userId, CanonicalKind(kind), targetId, cancellationToken));

    public Task<ServiceResult<TrainerDocumentOpenResultDto>> OpenAsync(
        Guid userId, Guid grantId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var ticket = NewToken();
            var expiresAtUtc = timeProvider.GetUtcNow().UtcDateTime.AddMinutes(Math.Max(1, options.Value.TicketLifetimeMinutes));

            var token = await documentsProvider.IssueTicketAsync(userId, grantId, HashTicket(ticket), expiresAtUtc, cancellationToken)
                ?? throw new NotFoundException($"User {userId} asked to open grant {grantId} they don't hold.",
                    "This document is no longer shared with you.");

            return new TrainerDocumentOpenResultDto
            {
                ViewerUrl = $"{options.Value.PublicBaseUrl.TrimEnd('/')}{ViewerPath(token)}?t={Uri.EscapeDataString(ticket)}",
                ExpiresAtUtc = expiresAtUtc
            };
        });

    /* -------------------------------- viewer -------------------------------- */

    public async Task<TrainerDocumentViewModel> ResolveGrantViewAsync(
        string token, string? ticket, string? adminSessionToken, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(token) || token.Length > 64)
        {
            return Denied();
        }

        var access = await documentsProvider.GetByTokenAsync(token, cancellationToken);
        if (access is null)
        {
            return Denied();
        }

        if (!string.IsNullOrEmpty(ticket) && TicketMatches(access, ticket))
        {
            var holder = access.DisplayName ?? access.Email ?? "SilaFit user";
            var watermark = string.Join(" · ", new[]
            {
                holder,
                access.Email is not null && access.Email != holder ? access.Email : null,
                timeProvider.GetUtcNow().UtcDateTime.ToString("yyyy-MM-dd HH:mm 'UTC'", CultureInfo.InvariantCulture)
            }.Where(part => part is not null));

            return new TrainerDocumentViewModel
            {
                Allowed = true,
                Title = access.Title,
                Watermark = watermark,
                TrainerUsername = access.TrainerUsername,
                FilePath = StoredPath(access.StoredFileName),
                GrantId = access.GrantId
            };
        }

        var operatorName = await ConsoleViewerAsync(access.Kind, access.TargetOwnerAdminUserId, adminSessionToken, cancellationToken);
        if (operatorName is null)
        {
            return Denied();
        }

        return new TrainerDocumentViewModel
        {
            Allowed = true,
            IsPreview = true,
            Title = access.Title,
            Watermark = $"Preview · {operatorName} · copy for {access.DisplayName ?? access.Email ?? "client"}",
            TrainerUsername = access.TrainerUsername,
            FilePath = StoredPath(access.StoredFileName)
        };
    }

    public async Task<TrainerDocumentViewModel> ResolvePreviewAsync(
        Guid documentId, string? adminSessionToken, CancellationToken cancellationToken = default)
    {
        var document = await documentsProvider.GetAsync(documentId, cancellationToken);
        if (document is null)
        {
            return Denied();
        }

        var operatorName = await ConsoleViewerAsync(document.Kind, document.TargetOwnerAdminUserId, adminSessionToken, cancellationToken);
        if (operatorName is null)
        {
            return Denied();
        }

        return new TrainerDocumentViewModel
        {
            Allowed = true,
            IsPreview = true,
            Title = document.Title,
            Watermark = $"Preview · {operatorName}",
            FilePath = StoredPath(document.StoredFileName)
        };
    }

    public Task RecordOpenAsync(Guid grantId, CancellationToken cancellationToken = default) =>
        documentsProvider.RecordOpenAsync(grantId, cancellationToken);

    /* ------------------------------- helpers -------------------------------- */

    /// <summary>The 256-bit random value behind both link tokens and tickets, URL-safe.</summary>
    public static string NewToken() => Base64Url(RandomNumberGenerator.GetBytes(32));

    public static byte[] HashTicket(string ticket) => SHA256.HashData(Encoding.UTF8.GetBytes(ticket));

    public static string ViewerPath(string token) => $"/api/documents/view/{token}";

    public static string CanonicalKind(string? kind) =>
        kind?.Trim().ToLowerInvariant() switch
        {
            "split" => KindSplit,
            "dietplan" or "diet-plan" or "diet_plan" => KindDietPlan,
            _ => throw new ValidationException($"Unknown document kind '{kind}'.", "Kind must be Split or DietPlan.")
        };

    /// <summary>The <c>?t=</c> value opens the grant when it is either the app's short-lived
    /// ticket or the link from the client's latest assignment email, and the grant is live.</summary>
    private bool TicketMatches(TrainerDocumentAccessModel access, string ticket)
    {
        if (access.RevokedAtUtc is not null || ticket.Length > 64)
        {
            return false;
        }

        var hash = HashTicket(ticket);
        var nowUtc = timeProvider.GetUtcNow().UtcDateTime;
        return Matches(access.TicketHash, access.TicketExpiresAtUtc, hash, nowUtc)
            | Matches(access.EmailLinkHash, access.EmailLinkExpiresAtUtc, hash, nowUtc);
    }

    private static bool Matches(byte[]? storedHash, DateTime? expiresAtUtc, byte[] hash, DateTime nowUtc) =>
        storedHash is { Length: 32 }
        && expiresAtUtc is { } expires
        && expires > nowUtc
        && CryptographicOperations.FixedTimeEquals(storedHash, hash);

    /// <summary>The operator's name when the console session may manage a document of this
    /// kind on this target (owner, or manage-all); otherwise null. Never throws on a bad cookie.</summary>
    private async Task<string?> ConsoleViewerAsync(string kind, Guid? targetOwner, string? adminSessionToken, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(adminSessionToken))
        {
            return null;
        }

        var session = await adminProvider.GetSessionAsync(AdminSessionTokenFactory.HashToken(adminSessionToken), cancellationToken);
        if (session is null)
        {
            return null;
        }

        var permissions = await adminRbacProvider.GetPermissionsAsync(session.AdminUserId, cancellationToken);
        var (read, manageAll) = kind == KindSplit
            ? (AdminPermissions.SplitsRead, AdminPermissions.SplitsManageAll)
            : (AdminPermissions.DietPlansRead, AdminPermissions.DietPlansManageAll);

        var allowed = permissions.Contains(read)
            && (permissions.Contains(manageAll) || targetOwner == session.AdminUserId);
        return allowed ? session.Username : null;
    }

    private async Task<(AdminActorModel Actor, bool CanManageAll)> RequireForKindAsync(
        string? sessionToken, string kind, string splitPermission, string dietPlanPermission, string? clientIp, CancellationToken cancellationToken)
    {
        var (permission, manageAll) = kind == KindSplit
            ? (splitPermission, AdminPermissions.SplitsManageAll)
            : (dietPlanPermission, AdminPermissions.DietPlansManageAll);

        var (actor, permissions) = await AdminPermissionGuard.RequireWithPermissionsAsync(
            adminProvider, adminRbacProvider, sessionToken, permission, clientIp, cancellationToken);
        return (actor, permissions.Contains(manageAll));
    }

    private async Task<TrainerDocumentFileModel> RequireDocumentAsync(Guid documentId, CancellationToken cancellationToken) =>
        await documentsProvider.GetAsync(documentId, cancellationToken)
        ?? throw new NotFoundException($"No trainer document {documentId}.", "That document no longer exists.");

    private string StorageDirectory() => Path.GetFullPath(options.Value.StoragePath);

    /// <summary>Stored names are generated here ("{guid}.pdf"); anything else is refused
    /// rather than joined into a path.</summary>
    private string StoredPath(string storedFileName)
    {
        if (storedFileName.Length != 36 || !storedFileName.EndsWith(".pdf", StringComparison.Ordinal)
            || !Guid.TryParseExact(storedFileName[..32], "N", out _))
        {
            throw new InvalidOperationException("Unexpected stored document name.");
        }
        return Path.Combine(StorageDirectory(), storedFileName);
    }

    private void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            logger.LogWarning(exception, "Could not delete trainer document file {FileName}.", Path.GetFileName(path));
        }
    }

    private static TrainerDocumentViewModel Denied() => new() { Allowed = false };

    private static string DocumentTitle(string? title, string fileName)
    {
        var value = string.IsNullOrWhiteSpace(title) ? Path.GetFileNameWithoutExtension(fileName) : title;
        value = value.Trim();
        if (value.Length == 0)
        {
            value = "Trainer document";
        }
        return value.Length > 200 ? value[..200] : value;
    }

    private static string OriginalName(string fileName)
    {
        var name = Path.GetFileName(fileName).Trim();
        return name.Length > 260 ? name[^260..] : name;
    }

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
