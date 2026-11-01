using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Moq;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public sealed class TrainerAssignmentNotifierTests
{
    private readonly Mock<ITrainerDocumentsProvider> documentsProvider = new();
    private readonly Mock<INotificationProvider> notificationProvider = new();
    private readonly Mock<IPushNotificationSender> pushSender = new();
    private readonly Mock<IEmailSender> emailSender = new();
    private readonly AdminActorModel actor = new() { AdminUserId = Guid.NewGuid(), Username = "coach" };
    private readonly Guid userId = Guid.NewGuid();
    private readonly Guid splitId = Guid.NewGuid();

    private TrainerAssignmentNotifier CreateSut(string smtpHost = "smtp.example.com", bool notify = true) => new(
        documentsProvider.Object,
        notificationProvider.Object,
        pushSender.Object,
        emailSender.Object,
        Options.Create(new TrainerDocumentOptions
        {
            PublicBaseUrl = "https://api.example.com/",
            EmailLinkLifetimeHours = 72,
            NotifyClientsOnAssign = notify
        }),
        Options.Create(new SmtpOptions { Host = smtpHost }),
        TimeProvider.System,
        NullLogger<TrainerAssignmentNotifier>.Instance);

    private void ArrangeContext(bool notificationsEnabled = true, string? email = "mila@example.com") =>
        documentsProvider.Setup(p => p.GetAssignmentNotifyContextAsync(userId, "Split", splitId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new TrainerAssignmentNotifyContextModel
            {
                UserId = userId,
                DisplayName = "Mila",
                Email = email,
                NotificationsEnabled = notificationsEnabled,
                ProgramName = "Hypertrophy block",
                TrainerUsername = "coach"
            });

    private UserTrainerDocumentModel ArrangeHeldDocument(Guid documentId)
    {
        var held = new UserTrainerDocumentModel { GrantId = Guid.NewGuid(), DocumentId = documentId, Title = "Week plan", Kind = "Split" };
        documentsProvider.Setup(p => p.GetForUserAsync(userId, "Split", splitId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([held]);
        documentsProvider.Setup(p => p.IssueEmailLinkAsync(held.GrantId, It.IsAny<byte[]>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync("grant-token");
        return held;
    }

    [Fact]
    public async Task ProgramAssigned_SharesDocuments_PushesAndEmailsSecureLink()
    {
        var documentId = Guid.NewGuid();
        documentsProvider.Setup(p => p.GetForTargetAsync("Split", splitId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([new TrainerDocumentModel { DocumentId = documentId, Kind = "Split", SplitId = splitId }]);
        documentsProvider.Setup(p => p.AssignAsync(documentId, userId, It.IsAny<string>(), true, actor, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminMutationResultModel { Outcome = 0 });
        ArrangeContext();
        var held = ArrangeHeldDocument(documentId);

        var notification = new UserNotificationModel { NotificationId = Guid.NewGuid(), UserId = userId, Category = NotificationCategories.TrainerProgramAssigned };
        notificationProvider.Setup(p => p.TryCreateNotificationAsync(It.IsAny<NewNotificationModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(notification);
        notificationProvider.Setup(p => p.GetActiveDeviceTokensAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([new UserDeviceTokenModel { PushToken = "device", Platform = "ios" }]);
        pushSender.Setup(p => p.SendAsync(It.IsAny<PushNotificationMessage>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(PushSendResult.Sent("msg-1"));

        byte[]? storedHash = null;
        documentsProvider.Setup(p => p.IssueEmailLinkAsync(held.GrantId, It.IsAny<byte[]>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Callback<Guid, byte[], DateTime, CancellationToken>((_, hash, _, _) => storedHash = hash)
            .ReturnsAsync("grant-token");
        string? html = null;
        emailSender.Setup(p => p.SendAsync("mila@example.com", It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .Callback<string, string, string, CancellationToken>((_, _, body, _) => html = body)
            .Returns(Task.CompletedTask);

        await CreateSut().NotifyProgramAssignedAsync("Split", splitId, userId, actor, true);

        documentsProvider.Verify(p => p.AssignAsync(documentId, userId, It.IsAny<string>(), true, actor, It.IsAny<CancellationToken>()), Times.Once);
        notificationProvider.Verify(p => p.TryCreateNotificationAsync(
            It.Is<NewNotificationModel>(n => n.Category == NotificationCategories.TrainerProgramAssigned && n.Body.Contains("Hypertrophy block")),
            It.IsAny<CancellationToken>()), Times.Once);
        notificationProvider.Verify(p => p.MarkSentAsync(notification.NotificationId, It.IsAny<string>(), "msg-1", It.IsAny<DateTime>(), It.IsAny<CancellationToken>()), Times.Once);

        // The email carries the link value; only its hash was stored.
        Assert.NotNull(html);
        var marker = "https://api.example.com/api/documents/view/grant-token?t=";
        var start = html!.IndexOf(marker, StringComparison.Ordinal);
        Assert.True(start >= 0);
        var secret = html[(start + marker.Length)..].Split('"')[0];
        Assert.Equal(TrainerDocumentService.HashTicket(Uri.UnescapeDataString(secret)), storedHash);
    }

    [Fact]
    public async Task ProgramAssigned_NotificationsOff_EmailsButDoesNotPush()
    {
        documentsProvider.Setup(p => p.GetForTargetAsync("Split", splitId, It.IsAny<CancellationToken>())).ReturnsAsync([]);
        documentsProvider.Setup(p => p.GetForUserAsync(userId, "Split", splitId, It.IsAny<CancellationToken>())).ReturnsAsync([]);
        ArrangeContext(notificationsEnabled: false);

        await CreateSut().NotifyProgramAssignedAsync("Split", splitId, userId, actor, true);

        notificationProvider.Verify(p => p.TryCreateNotificationAsync(It.IsAny<NewNotificationModel>(), It.IsAny<CancellationToken>()), Times.Never);
        emailSender.Verify(p => p.SendAsync("mila@example.com", It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task ProgramAssigned_WithoutSmtp_IssuesNoEmailLinks()
    {
        documentsProvider.Setup(p => p.GetForTargetAsync("Split", splitId, It.IsAny<CancellationToken>())).ReturnsAsync([]);
        ArrangeContext(notificationsEnabled: false);
        ArrangeHeldDocument(Guid.NewGuid());

        await CreateSut(smtpHost: "").NotifyProgramAssignedAsync("Split", splitId, userId, actor, true);

        documentsProvider.Verify(p => p.IssueEmailLinkAsync(It.IsAny<Guid>(), It.IsAny<byte[]>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()), Times.Never);
        emailSender.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task ProgramAssigned_FailureIsSwallowed()
    {
        documentsProvider.Setup(p => p.GetForTargetAsync("Split", splitId, It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("db down"));

        await CreateSut().NotifyProgramAssignedAsync("Split", splitId, userId, actor, true);
    }

    [Fact]
    public async Task DocumentShared_EmailsOnlyThatDocument()
    {
        var documentId = Guid.NewGuid();
        ArrangeContext(notificationsEnabled: false);
        ArrangeHeldDocument(documentId);
        string? subject = null;
        emailSender.Setup(p => p.SendAsync("mila@example.com", It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .Callback<string, string, string, CancellationToken>((_, s, _, _) => subject = s)
            .Returns(Task.CompletedTask);

        await CreateSut().NotifyDocumentSharedAsync(
            new TrainerDocumentFileModel { DocumentId = documentId, Kind = "Split", SplitId = splitId }, userId, actor);

        Assert.Equal("coach shared a split document with you", subject);
        documentsProvider.Verify(p => p.GetForTargetAsync(It.IsAny<string>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
    }
}
