using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Moq;
using Silen.Common.Authorization;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public sealed class TrainerDocumentServiceTests : IDisposable
{
    private readonly Mock<IAdminProvider> adminProvider = new(MockBehavior.Strict);
    private readonly Mock<IAdminRbacProvider> adminRbacProvider = new(MockBehavior.Strict);
    private readonly Mock<ITrainerDocumentsProvider> documentsProvider = new(MockBehavior.Strict);
    private readonly Mock<IDocumentProcessor> documentProcessor = new(MockBehavior.Strict);
    private readonly Mock<ITrainerDocumentAiImporter> aiImporter = new(MockBehavior.Strict);
    private readonly Mock<ITrainerAssignmentNotifier> assignmentNotifier = new();
    private readonly string storage = Path.Combine(Path.GetTempPath(), "silen-docs-" + Guid.NewGuid().ToString("N"));
    private readonly TrainerDocumentService sut;

    public TrainerDocumentServiceTests()
    {
        sut = new TrainerDocumentService(
            adminProvider.Object, adminRbacProvider.Object, documentsProvider.Object, documentProcessor.Object, aiImporter.Object, assignmentNotifier.Object,
            Options.Create(new TrainerDocumentOptions { StoragePath = storage, PublicBaseUrl = "https://api.example.com/" }),
            TimeProvider.System, NullLogger<TrainerDocumentService>.Instance);
    }

    public void Dispose()
    {
        if (Directory.Exists(storage))
        {
            Directory.Delete(storage, true);
        }
    }

    private (string Token, Guid AdminUserId) ArrangeSession(params string[] permissions)
    {
        const string sessionToken = "session-token";
        var adminUserId = Guid.NewGuid();
        adminProvider.Setup(p => p.GetSessionAsync(AdminSessionTokenFactory.HashToken(sessionToken), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminSessionModel { AdminUserId = adminUserId, Username = "coach" });
        adminRbacProvider.Setup(p => p.GetPermissionsAsync(adminUserId, It.IsAny<CancellationToken>())).ReturnsAsync(permissions.ToList());
        return (sessionToken, adminUserId);
    }

    private static AdminMutationResultModel Success(Guid id) => new() { Outcome = (int)AdminWriteOutcome.Success, EntityId = id };

    private static TrainerDocumentAccessModel Access(string ticket, DateTime expires, Guid? owner = null) => new()
    {
        GrantId = Guid.NewGuid(),
        DocumentId = Guid.NewGuid(),
        DisplayName = "Mila",
        Email = "mila@example.com",
        Title = "Hypertrophy block",
        Kind = "Split",
        StoredFileName = $"{Guid.NewGuid():N}.pdf",
        TicketHash = TrainerDocumentService.HashTicket(ticket),
        TicketExpiresAtUtc = expires,
        TargetOwnerAdminUserId = owner,
        TrainerUsername = "coach"
    };

    [Fact]
    public async Task OpenAsync_StoresOnlyTheTicketHash_AndReturnsViewerUrl()
    {
        var userId = Guid.NewGuid();
        var grantId = Guid.NewGuid();
        byte[]? storedHash = null;
        documentsProvider.Setup(p => p.IssueTicketAsync(userId, grantId, It.IsAny<byte[]>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Callback<Guid, Guid, byte[], DateTime, CancellationToken>((_, _, hash, _, _) => storedHash = hash)
            .ReturnsAsync("link-token");

        var result = await sut.OpenAsync(userId, grantId);

        Assert.True(result.IsSuccess);
        Assert.StartsWith("https://api.example.com/api/documents/view/link-token?t=", result.Data!.ViewerUrl);
        var ticket = Uri.UnescapeDataString(result.Data.ViewerUrl.Split("?t=")[1]);
        Assert.Equal(TrainerDocumentService.HashTicket(ticket), storedHash);
    }

    [Fact]
    public async Task OpenAsync_GrantNotTheCallers_IsNotFound()
    {
        documentsProvider.Setup(p => p.IssueTicketAsync(It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<byte[]>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((string?)null);

        var result = await sut.OpenAsync(Guid.NewGuid(), Guid.NewGuid());

        Assert.False(result.IsSuccess);
        Assert.Equal(404, result.StatusCode);
    }

    [Fact]
    public async Task ResolveGrantView_ValidTicket_RendersWithHolderWatermark()
    {
        var access = Access("ticket-1", DateTime.UtcNow.AddMinutes(5));
        documentsProvider.Setup(p => p.GetByTokenAsync("tok", It.IsAny<CancellationToken>())).ReturnsAsync(access);

        var view = await sut.ResolveGrantViewAsync("tok", "ticket-1", null);

        Assert.True(view.Allowed);
        Assert.False(view.IsPreview);
        Assert.Equal(access.GrantId, view.GrantId);
        Assert.StartsWith("Mila · mila@example.com", view.Watermark);
    }

    [Theory]
    [InlineData("wrong-ticket", 5)]
    [InlineData("ticket-1", -1)]
    [InlineData(null, 5)]
    public async Task ResolveGrantView_BadOrExpiredOrMissingTicket_WithoutConsoleSession_IsDenied(string? ticket, int minutes)
    {
        documentsProvider.Setup(p => p.GetByTokenAsync("tok", It.IsAny<CancellationToken>()))
            .ReturnsAsync(Access("ticket-1", DateTime.UtcNow.AddMinutes(minutes)));

        var view = await sut.ResolveGrantViewAsync("tok", ticket, null);

        Assert.False(view.Allowed);
    }

    [Fact]
    public async Task ResolveGrantView_RevokedGrant_IsDeniedEvenWithTicket()
    {
        var access = Access("ticket-1", DateTime.UtcNow.AddMinutes(5));
        access.RevokedAtUtc = DateTime.UtcNow;
        documentsProvider.Setup(p => p.GetByTokenAsync("tok", It.IsAny<CancellationToken>())).ReturnsAsync(access);

        Assert.False((await sut.ResolveGrantViewAsync("tok", "ticket-1", null)).Allowed);
    }

    [Fact]
    public async Task ResolveGrantView_OwningTrainerSession_GetsPreview()
    {
        var (session, adminUserId) = ArrangeSession(AdminPermissions.SplitsRead);
        documentsProvider.Setup(p => p.GetByTokenAsync("tok", It.IsAny<CancellationToken>()))
            .ReturnsAsync(Access("ticket-1", DateTime.UtcNow.AddMinutes(5), adminUserId));

        var view = await sut.ResolveGrantViewAsync("tok", null, session);

        Assert.True(view.Allowed);
        Assert.True(view.IsPreview);
        Assert.Null(view.GrantId);
    }

    [Fact]
    public async Task ResolveGrantView_OtherTrainersDocument_WithoutManageAll_IsDenied()
    {
        var (session, _) = ArrangeSession(AdminPermissions.SplitsRead);
        documentsProvider.Setup(p => p.GetByTokenAsync("tok", It.IsAny<CancellationToken>()))
            .ReturnsAsync(Access("ticket-1", DateTime.UtcNow.AddMinutes(5), Guid.NewGuid()));

        Assert.False((await sut.ResolveGrantViewAsync("tok", null, session)).Allowed);
    }

    [Fact]
    public async Task UploadAsync_AttachToExisting_StoresPdfAndCreatesRow()
    {
        var (session, _) = ArrangeSession(AdminPermissions.SplitsWrite);
        var splitId = Guid.NewGuid();
        var documentId = Guid.NewGuid();
        documentProcessor.Setup(p => p.NormalizeToPdfAsync(It.IsAny<byte[]>(), ".docx", It.IsAny<CancellationToken>()))
            .ReturnsAsync("%PDF-1.7 converted"u8.ToArray());
        string? storedName = null;
        documentsProvider.Setup(p => p.CreateAsync("Split", splitId, "Week plan", "Week plan.docx", It.IsAny<string>(), It.IsAny<long>(),
                false, It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .Callback<string, Guid, string, string, string, long, bool, AdminActorModel, CancellationToken>((_, _, _, _, name, _, _, _, _) => storedName = name)
            .ReturnsAsync(Success(documentId));

        using var content = new MemoryStream("docx bytes"u8.ToArray());
        var result = await sut.UploadAsync(session,
            new TrainerDocumentUploadRequest("split", splitId, null, false, content, "Week plan.docx", content.Length), null);

        Assert.True(result.IsSuccess, result.LogMessage);
        Assert.Equal(documentId, result.Data!.DocumentId);
        Assert.False(result.Data.Generated);
        Assert.True(File.Exists(Path.Combine(storage, storedName!)));
    }

    [Fact]
    public async Task UploadAsync_GenerateFromScannedPdf_AsksToAttachWithoutAi()
    {
        var (session, _) = ArrangeSession(AdminPermissions.DietPlansWrite);
        documentProcessor.Setup(p => p.NormalizeToPdfAsync(It.IsAny<byte[]>(), ".pdf", It.IsAny<CancellationToken>()))
            .ReturnsAsync("%PDF-1.7"u8.ToArray());
        documentProcessor.Setup(p => p.ExtractText(It.IsAny<byte[]>(), It.IsAny<int>())).Returns("  ");

        using var content = new MemoryStream("%PDF-1.7"u8.ToArray());
        var result = await sut.UploadAsync(session,
            new TrainerDocumentUploadRequest("DietPlan", null, null, true, content, "scan.pdf", content.Length), null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task UploadAsync_GenerateSplit_ImportsThenAttaches()
    {
        var (session, _) = ArrangeSession(AdminPermissions.SplitsWrite);
        var newSplitId = Guid.NewGuid();
        const string text = "Week 1 Monday: Bench press 4x8, Squat 4x6. Tuesday rest. Wednesday deadlift 3x5.";
        documentProcessor.Setup(p => p.NormalizeToPdfAsync(It.IsAny<byte[]>(), ".pdf", It.IsAny<CancellationToken>()))
            .ReturnsAsync("%PDF-1.7"u8.ToArray());
        documentProcessor.Setup(p => p.ExtractText(It.IsAny<byte[]>(), It.IsAny<int>())).Returns(text);
        aiImporter.Setup(p => p.ReadSplitAsync(text, "program", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ImportedProgram("Strength", "Intermediate", null, 14, 9, "[]"));
        documentsProvider.Setup(p => p.ImportSplitAsync("Strength", "Intermediate", null, 14, "[]", It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(Success(newSplitId));
        documentsProvider.Setup(p => p.CreateAsync("Split", newSplitId, "program", "program.pdf", It.IsAny<string>(), It.IsAny<long>(),
                false, It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(Success(Guid.NewGuid()));

        using var content = new MemoryStream("%PDF-1.7"u8.ToArray());
        var result = await sut.UploadAsync(session,
            new TrainerDocumentUploadRequest("Split", null, null, true, content, "program.pdf", content.Length), null);

        Assert.True(result.IsSuccess, result.LogMessage);
        Assert.True(result.Data!.Generated);
        Assert.Equal(newSplitId, result.Data.TargetId);
        Assert.Equal(2, result.Data.GeneratedWeeks);
    }

    [Fact]
    public async Task UploadAsync_WrongExtension_IsRejected()
    {
        var (session, _) = ArrangeSession(AdminPermissions.SplitsWrite);
        using var content = new MemoryStream([1, 2, 3]);

        var result = await sut.UploadAsync(session,
            new TrainerDocumentUploadRequest("Split", Guid.NewGuid(), null, false, content, "plan.xlsx", 3), null);

        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task UploadAsync_WithoutWritePermission_IsForbidden()
    {
        var (session, _) = ArrangeSession(AdminPermissions.SplitsRead);
        using var content = new MemoryStream([1]);

        var result = await sut.UploadAsync(session,
            new TrainerDocumentUploadRequest("Split", Guid.NewGuid(), null, false, content, "plan.pdf", 1), null);

        Assert.Equal(403, result.StatusCode);
    }

    [Fact]
    public async Task RevokeAsync_GrantFromAnotherDocument_IsNotFound()
    {
        var (session, _) = ArrangeSession(AdminPermissions.SplitsAssign);
        var documentId = Guid.NewGuid();
        documentsProvider.Setup(p => p.GetAsync(documentId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new TrainerDocumentFileModel { DocumentId = documentId, Kind = "Split", StoredFileName = $"{Guid.NewGuid():N}.pdf" });
        documentsProvider.Setup(p => p.GetGrantsAsync(documentId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([new TrainerDocumentGrantModel { GrantId = Guid.NewGuid() }]);

        var result = await sut.RevokeAsync(session, documentId, Guid.NewGuid(), null);

        Assert.Equal(404, result.StatusCode);
    }

    [Fact]
    public async Task ResolveGrantView_EmailLink_OpensAlongsideTheAppTicket()
    {
        var access = Access("app-ticket", DateTime.UtcNow.AddMinutes(5));
        access.EmailLinkHash = TrainerDocumentService.HashTicket("email-link");
        access.EmailLinkExpiresAtUtc = DateTime.UtcNow.AddHours(48);
        documentsProvider.Setup(p => p.GetByTokenAsync("tok", It.IsAny<CancellationToken>())).ReturnsAsync(access);

        Assert.True((await sut.ResolveGrantViewAsync("tok", "email-link", null)).Allowed);
        Assert.True((await sut.ResolveGrantViewAsync("tok", "app-ticket", null)).Allowed);
    }

    [Fact]
    public async Task ResolveGrantView_ExpiredOrRevokedEmailLink_IsDenied()
    {
        var expired = Access("app-ticket", DateTime.UtcNow.AddMinutes(-1));
        expired.EmailLinkHash = TrainerDocumentService.HashTicket("email-link");
        expired.EmailLinkExpiresAtUtc = DateTime.UtcNow.AddMinutes(-1);
        documentsProvider.Setup(p => p.GetByTokenAsync("expired", It.IsAny<CancellationToken>())).ReturnsAsync(expired);

        var revoked = Access("app-ticket", DateTime.UtcNow.AddMinutes(5));
        revoked.EmailLinkHash = TrainerDocumentService.HashTicket("email-link");
        revoked.EmailLinkExpiresAtUtc = DateTime.UtcNow.AddHours(48);
        revoked.RevokedAtUtc = DateTime.UtcNow;
        documentsProvider.Setup(p => p.GetByTokenAsync("revoked", It.IsAny<CancellationToken>())).ReturnsAsync(revoked);

        Assert.False((await sut.ResolveGrantViewAsync("expired", "email-link", null)).Allowed);
        Assert.False((await sut.ResolveGrantViewAsync("revoked", "email-link", null)).Allowed);
    }

    [Fact]
    public void ViewerPage_EncodesTitleAndWatermark()
    {
        var html = TrainerDocumentViewerPage.Render("<script>x</script>", "A \"B\"", "coach", false, "tok/file?t=a&b");

        Assert.DoesNotContain("<script>x", html);
        Assert.Contains("&lt;script&gt;", html);
        Assert.Contains("data-file=\"tok/file?t=a&amp;b\"", html);
    }
}
