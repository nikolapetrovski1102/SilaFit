using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>
/// Trainer documents (TrainerDocuments.sql) and the AI document imports
/// (AdminDocumentImports.sql). Ownership checks happen in SQL: every console write
/// takes canManageAll and refuses a document whose split / plan another trainer owns.
/// </summary>
public interface ITrainerDocumentsProvider
{
    Task<List<TrainerDocumentModel>> GetForTargetAsync(string kind, Guid targetId, CancellationToken cancellationToken = default);

    Task<TrainerDocumentFileModel?> GetAsync(Guid documentId, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> CreateAsync(
        string kind, Guid targetId, string title, string originalFileName, string storedFileName, long sizeBytes,
        bool canManageAll, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteAsync(Guid documentId, bool canManageAll, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<List<TrainerDocumentGrantModel>> GetGrantsAsync(Guid documentId, CancellationToken cancellationToken = default);

    /// <summary>Gives (or gives back) the document to a client. A live grant keeps its
    /// token; a revoked one comes back with <paramref name="token"/>.</summary>
    Task<AdminMutationResultModel> AssignAsync(
        Guid documentId, Guid userId, string token, bool canManageAll, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> RevokeAsync(Guid grantId, bool canManageAll, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<TrainerDocumentAccessModel?> GetByTokenAsync(string token, CancellationToken cancellationToken = default);

    Task RecordOpenAsync(Guid grantId, CancellationToken cancellationToken = default);

    Task<List<UserTrainerDocumentModel>> GetForUserAsync(Guid userId, string kind, Guid targetId, CancellationToken cancellationToken = default);

    /// <summary>Stores a ticket hash on the caller's own live grant and returns its link
    /// token, or null when the grant isn't theirs or was revoked.</summary>
    Task<string?> IssueTicketAsync(Guid userId, Guid grantId, byte[] ticketHash, DateTime expiresAtUtc, CancellationToken cancellationToken = default);

    /// <summary>Stores the hash of the link emailed to the grant's client (replacing any earlier
    /// one) and returns its link token, or null when the grant was revoked.</summary>
    Task<string?> IssueEmailLinkAsync(Guid grantId, byte[] linkHash, DateTime expiresAtUtc, CancellationToken cancellationToken = default);

    /// <summary>The client and program behind an assignment, or null when either is gone.</summary>
    Task<TrainerAssignmentNotifyContextModel?> GetAssignmentNotifyContextAsync(
        Guid userId, string kind, Guid targetId, CancellationToken cancellationToken = default);

    /// <summary>Creates a private split owned by the actor from AI-extracted JSON days.</summary>
    Task<AdminMutationResultModel> ImportSplitAsync(
        string name, string level, string? description, int durationDays, string daysJson,
        AdminActorModel actor, CancellationToken cancellationToken = default);

    /// <summary>Creates a private diet plan (and its trainer-owned meals) from AI-extracted JSON days.</summary>
    Task<AdminMutationResultModel> ImportDietPlanAsync(
        string name, string? description, int durationDays, string daysJson,
        AdminActorModel actor, CancellationToken cancellationToken = default);
}
