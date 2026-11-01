using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>
/// Tells a client their trainer gave them something: a push to their devices and an
/// email with personal, expiring links to the program's PDFs. Runs after the console
/// write has committed and never throws - a failed push or email is logged, it never
/// turns a successful assignment into an error for the trainer.
/// </summary>
public interface ITrainerAssignmentNotifier
{
    /// <summary>A split (<c>kind=Split</c>) or diet plan (<c>kind=DietPlan</c>) was assigned. Also shares
    /// the program's documents with the client so the email can link to them.</summary>
    Task NotifyProgramAssignedAsync(
        string kind, Guid targetId, Guid userId, AdminActorModel actor, bool canManageAll,
        CancellationToken cancellationToken = default);

    /// <summary>One document was shared with the client from the console.</summary>
    Task NotifyDocumentSharedAsync(
        TrainerDocumentFileModel document, Guid userId, AdminActorModel actor,
        CancellationToken cancellationToken = default);
}
