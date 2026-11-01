using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="ITrainerAssignmentNotifier"/>
/// <remarks>
/// Email links reuse the document viewer and its per-client link token; what makes
/// one open is a separate random value (only its SHA-256 is stored, on the grant)
/// that expires after <see cref="TrainerDocumentOptions.EmailLinkLifetimeHours"/>,
/// is replaced by the next email, and is cleared when the grant is revoked.
/// </remarks>
public sealed class TrainerAssignmentNotifier(
    ITrainerDocumentsProvider documentsProvider,
    INotificationProvider notificationProvider,
    IPushNotificationSender pushSender,
    IEmailSender emailSender,
    IOptions<TrainerDocumentOptions> documentOptions,
    IOptions<SmtpOptions> smtpOptions,
    TimeProvider timeProvider,
    ILogger<TrainerAssignmentNotifier> logger) : ITrainerAssignmentNotifier
{
    public async Task NotifyProgramAssignedAsync(
        string kind, Guid targetId, Guid userId, AdminActorModel actor, bool canManageAll,
        CancellationToken cancellationToken = default)
    {
        try
        {
            await ShareProgramDocumentsAsync(kind, targetId, userId, actor, canManageAll, cancellationToken);

            if (!documentOptions.Value.NotifyClientsOnAssign)
            {
                return;
            }

            var held = await documentsProvider.GetForUserAsync(userId, kind, targetId, cancellationToken);
            await NotifyAsync(kind, targetId, userId, actor, held, documentOnly: false,
                dedupeKey: $"trainerassign:{kind}:{targetId:N}:{Today():yyyyMMdd}", cancellationToken);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            logger.LogWarning(exception, "Could not notify user {UserId} about {Kind} {TargetId}.", userId, kind, targetId);
        }
    }

    public async Task NotifyDocumentSharedAsync(
        TrainerDocumentFileModel document, Guid userId, AdminActorModel actor,
        CancellationToken cancellationToken = default)
    {
        try
        {
            if (!documentOptions.Value.NotifyClientsOnAssign)
            {
                return;
            }

            var targetId = (document.Kind == TrainerDocumentService.KindSplit ? document.SplitId : document.DietPlanId)
                ?? throw new InvalidOperationException($"Document {document.DocumentId} has no target.");

            var held = (await documentsProvider.GetForUserAsync(userId, document.Kind, targetId, cancellationToken))
                .Where(d => d.DocumentId == document.DocumentId)
                .ToList();
            if (held.Count == 0)
            {
                return;
            }

            await NotifyAsync(document.Kind, targetId, userId, actor, held, documentOnly: true,
                dedupeKey: $"trainerdoc:{document.DocumentId:N}:{Today():yyyyMMdd}", cancellationToken);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            logger.LogWarning(exception, "Could not notify user {UserId} about document {DocumentId}.", userId, document.DocumentId);
        }
    }

    /// <summary>Gives the client every document already attached to the program they were just
    /// assigned - the trainer would otherwise have to share each one by hand before the email
    /// had anything to link to. Uses the same ownership rules as sharing from the console.</summary>
    private async Task ShareProgramDocumentsAsync(
        string kind, Guid targetId, Guid userId, AdminActorModel actor, bool canManageAll, CancellationToken cancellationToken)
    {
        var documents = await documentsProvider.GetForTargetAsync(kind, targetId, cancellationToken);
        foreach (var document in documents)
        {
            var mutation = await documentsProvider.AssignAsync(
                document.DocumentId, userId, TrainerDocumentService.NewToken(), canManageAll, actor, cancellationToken);
            if (mutation.Result != AdminWriteOutcome.Success)
            {
                logger.LogInformation("Did not share document {DocumentId} with user {UserId} on assignment: {Message}",
                    document.DocumentId, userId, mutation.Detail);
            }
        }
    }

    private async Task NotifyAsync(
        string kind, Guid targetId, Guid userId, AdminActorModel actor,
        IReadOnlyList<UserTrainerDocumentModel> documents, bool documentOnly, string dedupeKey,
        CancellationToken cancellationToken)
    {
        var context = await documentsProvider.GetAssignmentNotifyContextAsync(userId, kind, targetId, cancellationToken);
        if (context is null)
        {
            return;
        }

        var isSplit = kind == TrainerDocumentService.KindSplit;
        var trainerName = context.TrainerUsername ?? (string.IsNullOrWhiteSpace(actor.Username) ? null : actor.Username);

        if (context.NotificationsEnabled)
        {
            var content = NotificationMessageComposer.TrainerProgramAssigned(isSplit, context.ProgramName, trainerName, documentOnly);
            var created = await notificationProvider.TryCreateNotificationAsync(new NewNotificationModel
            {
                UserId = userId,
                Category = NotificationCategories.TrainerProgramAssigned,
                Title = content.Title,
                Body = content.Body,
                DeepLink = content.Screen,
                DedupeKey = dedupeKey,
                ScheduledLocalAt = timeProvider.GetUtcNow().UtcDateTime
            }, cancellationToken);

            // Null means this exact notice already went out today (e.g. the trainer pressed assign twice).
            if (created is not null)
            {
                await UserPushDelivery.DeliverAsync(notificationProvider, pushSender, created, content.Screen, cancellationToken);
            }
        }

        if (string.IsNullOrWhiteSpace(context.Email) || string.IsNullOrWhiteSpace(smtpOptions.Value.Host))
        {
            return;
        }

        var links = new List<TrainerAssignmentEmailDocument>();
        var lifetimeHours = Math.Max(1, documentOptions.Value.EmailLinkLifetimeHours);
        var expiresAtUtc = timeProvider.GetUtcNow().UtcDateTime.AddHours(lifetimeHours);
        foreach (var document in documents)
        {
            var secret = TrainerDocumentService.NewToken();
            var token = await documentsProvider.IssueEmailLinkAsync(
                document.GrantId, TrainerDocumentService.HashTicket(secret), expiresAtUtc, cancellationToken);
            if (token is null)
            {
                continue;
            }

            links.Add(new TrainerAssignmentEmailDocument(
                document.Title,
                $"{documentOptions.Value.PublicBaseUrl.TrimEnd('/')}{TrainerDocumentService.ViewerPath(token)}?t={Uri.EscapeDataString(secret)}"));
        }

        // A document share with no live link left has nothing to say.
        if (documentOnly && links.Count == 0)
        {
            return;
        }

        var kindLabel = isSplit ? "split" : "diet plan";
        await emailSender.SendAsync(
            context.Email,
            TrainerAssignmentEmailRenderer.BuildSubject(kindLabel, context.ProgramName, trainerName, documentOnly),
            TrainerAssignmentEmailRenderer.BuildHtml(
                context.DisplayName, kindLabel, context.ProgramName, trainerName, documentOnly, links, lifetimeHours),
            cancellationToken);
    }

    private DateTime Today() => timeProvider.GetUtcNow().UtcDateTime.Date;
}
