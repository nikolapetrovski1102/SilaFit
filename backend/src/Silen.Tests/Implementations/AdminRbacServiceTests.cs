using System.Security.Cryptography;
using Microsoft.Extensions.Options;
using Moq;
using Silen.Common.Authorization;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class AdminRbacServiceTests
{
    private readonly Mock<IAdminProvider> adminProvider = new(MockBehavior.Strict);
    private readonly Mock<IAdminRbacProvider> adminRbacProvider = new(MockBehavior.Strict);
    private readonly Mock<IEmailSender> emailSender = new(MockBehavior.Strict);
    private readonly byte[] masterKey = RandomNumberGenerator.GetBytes(FieldCipher.KeySizeBytes);
    private readonly AdminRbacService sut;

    public AdminRbacServiceTests()
    {
        sut = new AdminRbacService(
            adminProvider.Object,
            adminRbacProvider.Object,
            emailSender.Object,
            Options.Create(new AdminAuthOptions { TotpIssuer = "Test Admin", TotpDigits = 6, TotpStepSeconds = 30 }),
            Options.Create(new JwtOptions { Issuer = "silafit-test", Audience = "silafit-test-aud", SigningKey = "unit-test-signing-key-unit-test-signing-key" }),
            Options.Create(new EncryptionOptions { MasterKeyBase64 = Convert.ToBase64String(masterKey) }));
    }

    private (string SessionToken, Guid AdminUserId, string Username) ArrangeSession(params string[] permissions)
    {
        const string sessionToken = "session-token";
        var adminUserId = Guid.NewGuid();
        const string username = "ops-admin";
        var session = new AdminSessionModel
        {
            AdminSessionId = Guid.NewGuid(),
            AdminUserId = adminUserId,
            Username = username,
            ExpiresAtUtc = DateTime.UtcNow.AddMinutes(30),
            AbsoluteExpiresAtUtc = DateTime.UtcNow.AddHours(8),
            LastSeenAtUtc = DateTime.UtcNow
        };
        adminProvider.Setup(p => p.GetSessionAsync(AdminSessionTokenFactory.HashToken(sessionToken), It.IsAny<CancellationToken>())).ReturnsAsync(session);
        adminRbacProvider.Setup(p => p.GetPermissionsAsync(adminUserId, It.IsAny<CancellationToken>())).ReturnsAsync(permissions.ToList());
        return (sessionToken, adminUserId, username);
    }

    /* ------------------------------- Authorization gate (representative) ------------------------------ */

    [Fact]
    public async Task GetPermissionCatalogAsync_WithoutRolesManagePermission_ReturnsForbiddenFailure()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.AuditRead);

        var result = await sut.GetPermissionCatalogAsync(token);

        Assert.False(result.IsSuccess);
        Assert.Equal(403, result.StatusCode);
    }

    [Fact]
    public async Task GetPermissionCatalogAsync_NoSession_ReturnsUnauthorizedFailure()
    {
        var result = await sut.GetPermissionCatalogAsync(null);

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
    }

    [Fact]
    public async Task GetPermissionCatalogAsync_WithRolesManagePermission_ReturnsTheFullCatalog()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.RolesManage);

        var result = await sut.GetPermissionCatalogAsync(token);

        Assert.True(result.IsSuccess);
        Assert.Equal(AdminPermissions.Catalog.Count, result.Data!.Count);
        Assert.Contains(result.Data, dto => dto.Permission == AdminPermissions.RolesManage);
    }

    /* ------------------------------- GetRolesAsync (N+1 orchestration) ------------------------------ */

    [Fact]
    public async Task GetRolesAsync_FetchesPermissionsPerRole_AndFallsBackToEmptyListWhenMissing()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.RolesManage);
        var roleWithPerms = new AdminRoleModel { RoleId = Guid.NewGuid(), Name = "Editor", Description = "Content editor", IsSystemRole = false, PermissionCount = 2, OperatorCount = 3 };
        var roleWithoutPerms = new AdminRoleModel { RoleId = Guid.NewGuid(), Name = "Ghost", Description = null, IsSystemRole = false, PermissionCount = 0, OperatorCount = 0 };

        adminRbacProvider.Setup(p => p.GetRolesAsync(It.IsAny<CancellationToken>())).ReturnsAsync([roleWithPerms, roleWithoutPerms]);
        adminRbacProvider.Setup(p => p.GetRolePermissionsAsync("Editor", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminRolePermissionSetModel { RoleName = "Editor", IsSystemRole = false, Permissions = [AdminPermissions.PlansRead] });
        adminRbacProvider.Setup(p => p.GetRolePermissionsAsync("Ghost", It.IsAny<CancellationToken>())).ReturnsAsync((AdminRolePermissionSetModel?)null);

        var result = await sut.GetRolesAsync(token);

        Assert.True(result.IsSuccess);
        Assert.Equal(2, result.Data!.Count);
        Assert.Equal([AdminPermissions.PlansRead], result.Data.Single(r => r.Name == "Editor").Permissions);
        Assert.Empty(result.Data.Single(r => r.Name == "Ghost").Permissions);
    }

    [Fact]
    public async Task GetRolePermissionsAsync_UnknownRoleName_ReturnsNotFoundFailure()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.RolesManage);
        adminRbacProvider.Setup(p => p.GetRolePermissionsAsync("ghost-role", It.IsAny<CancellationToken>())).ReturnsAsync((AdminRolePermissionSetModel?)null);

        var result = await sut.GetRolePermissionsAsync(token, "ghost-role");

        Assert.False(result.IsSuccess);
        Assert.Equal(404, result.StatusCode);
    }

    /* ------------------------------- Mutation outcome mapping ------------------------------ */

    [Fact]
    public async Task CreateRoleAsync_ProviderReportsConflict_ReturnsConflictFailure()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.RolesManage);
        var request = new AdminRoleCreateRequest { Name = "Editor", Description = "dup" };
        adminRbacProvider.Setup(p => p.CreateRoleAsync("Editor", "dup", It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminMutationResultModel { Outcome = (int)AdminWriteOutcome.Conflict, EntityId = null, Detail = "A role named 'Editor' already exists." });

        var result = await sut.CreateRoleAsync(token, request, "203.0.113.1");

        Assert.False(result.IsSuccess);
        Assert.Equal(409, result.StatusCode);
    }

    [Fact]
    public async Task DeleteRoleAsync_UnknownRole_ReturnsNotFoundFailure()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.RolesManage);
        adminRbacProvider.Setup(p => p.DeleteRoleAsync("ghost", It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminMutationResultModel { Outcome = (int)AdminWriteOutcome.NotFound, EntityId = null, Detail = "No role named 'ghost'." });

        var result = await sut.DeleteRoleAsync(token, "ghost", null);

        Assert.False(result.IsSuccess);
        Assert.Equal(404, result.StatusCode);
    }

    [Fact]
    public async Task SetOperatorActiveAsync_ProviderRejectsTheWrite_ReturnsValidationFailure()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.OperatorsManage);
        var request = new AdminOperatorActiveRequest { Username = "ops2", IsActive = false };
        adminRbacProvider.Setup(p => p.SetOperatorActiveAsync("ops2", false, It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminMutationResultModel { Outcome = (int)AdminWriteOutcome.Rejected, EntityId = null, Detail = "Cannot deactivate the last active operator." });

        var result = await sut.SetOperatorActiveAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SetOperatorActiveAsync_Success_ReturnsReactivatedOrDeactivatedMessage()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.OperatorsManage);
        var request = new AdminOperatorActiveRequest { Username = "ops2", IsActive = true };
        var entityId = Guid.NewGuid();
        adminRbacProvider.Setup(p => p.SetOperatorActiveAsync("ops2", true, It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminMutationResultModel { Outcome = (int)AdminWriteOutcome.Success, EntityId = entityId, Detail = null });

        var result = await sut.SetOperatorActiveAsync(token, request, null);

        Assert.True(result.IsSuccess);
        Assert.Equal("'ops2' reactivated.", result.Data!.Message);
    }

    /* ------------------------------- SetRolePermissionAsync validation ------------------------------ */

    [Fact]
    public async Task SetRolePermissionAsync_UnknownPermission_ReturnsValidationFailureWithoutCallingProvider()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.RolesManage);
        var request = new AdminRolePermissionRequest { RoleName = "Editor", Permission = "not.a.real.permission", Granted = true };

        var result = await sut.SetRolePermissionAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SetRolePermissionAsync_KnownPermission_GrantsAndReturnsSuccessMessage()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.RolesManage);
        var request = new AdminRolePermissionRequest { RoleName = "Editor", Permission = AdminPermissions.PlansWrite, Granted = true };
        adminRbacProvider.Setup(p => p.SetRolePermissionAsync("Editor", AdminPermissions.PlansWrite, true, It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminMutationResultModel { Outcome = (int)AdminWriteOutcome.Success, EntityId = Guid.NewGuid(), Detail = null });

        var result = await sut.SetRolePermissionAsync(token, request, null);

        Assert.True(result.IsSuccess);
        Assert.Equal($"'{AdminPermissions.PlansWrite}' granted to 'Editor'.", result.Data!.Message);
    }

    /* ------------------------------- CreateOperatorAsync validation + happy path ------------------------------ */

    [Fact]
    public async Task CreateOperatorAsync_BlankUsername_ReturnsValidationFailure()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.OperatorsManage);
        var request = new AdminOperatorCreateRequest { Username = "   ", Password = "a-long-enough-password" };

        var result = await sut.CreateOperatorAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task CreateOperatorAsync_BlankEmail_ReturnsValidationFailure()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.OperatorsManage);
        var request = new AdminOperatorCreateRequest { Username = "new-op", Email = "not-an-email", Password = "a-long-enough-password" };

        var result = await sut.CreateOperatorAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task CreateOperatorAsync_PasswordShorterThanMinimum_ReturnsValidationFailure()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.OperatorsManage);
        var request = new AdminOperatorCreateRequest { Username = "new-op", Email = "new-op@example.com", Password = "short" };

        var result = await sut.CreateOperatorAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task CreateOperatorAsync_UnknownRoleName_ReturnsValidationFailure()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.OperatorsManage);
        var request = new AdminOperatorCreateRequest { Username = "new-op", Email = "new-op@example.com", Password = "a-long-enough-password", RoleName = "Ghost" };
        adminRbacProvider.Setup(p => p.GetRolePermissionsAsync("Ghost", It.IsAny<CancellationToken>())).ReturnsAsync((AdminRolePermissionSetModel?)null);

        var result = await sut.CreateOperatorAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task CreateOperatorAsync_HappyPath_ReturnsEnrollmentSecretAndOtpAuthUri()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.OperatorsManage);
        var request = new AdminOperatorCreateRequest { Username = "new-op", Email = "new-op@example.com", Password = "a-long-enough-password", RoleName = null };
        var entityId = Guid.NewGuid();

        byte[]? capturedHash = null;
        byte[]? capturedSalt = null;
        byte[]? capturedCipher = null;
        adminRbacProvider.Setup(p => p.CreateOperatorAsync(
                "new-op", It.IsAny<byte[]>(), It.IsAny<byte[]>(), It.IsAny<byte[]>(), "new-op@example.com", null, It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .Callback<string, byte[], byte[], byte[], string, string?, AdminActorModel, CancellationToken>((_, hash, salt, cipher, _, _, _, _) =>
            {
                capturedHash = hash;
                capturedSalt = salt;
                capturedCipher = cipher;
            })
            .ReturnsAsync(new AdminMutationResultModel { Outcome = (int)AdminWriteOutcome.Success, EntityId = entityId, Detail = null });
        emailSender.Setup(e => e.SendAsync("new-op@example.com", It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.CreateOperatorAsync(token, request, null);

        Assert.True(result.IsSuccess);
        Assert.Equal(entityId, result.Data!.AdminUserId);
        Assert.Equal("new-op", result.Data.Username);
        Assert.Null(result.Data.RoleName);
        Assert.Equal(20, Base32Helper.Decode(result.Data.TotpSecret).Length);
        Assert.Contains("new-op", result.Data.OtpAuthUri);
        Assert.NotEmpty(capturedHash!);
        Assert.NotEmpty(capturedSalt!);
        Assert.NotEmpty(capturedCipher!);

        var decrypted = AdminTotpSecretCipher.Decrypt(capturedCipher!, masterKey);
        Assert.Equal(result.Data.TotpSecret, decrypted);
    }

    /* ------------------------------- ConfirmOperatorEmailAsync ------------------------------ */

    private static readonly JwtOptions ConfirmTokenOptions = new()
    {
        Issuer = "silafit-test",
        Audience = "silafit-test-aud",
        SigningKey = "unit-test-signing-key-unit-test-signing-key"
    };

    [Fact]
    public async Task ConfirmOperatorEmailAsync_InvalidToken_ReturnsUnauthorizedFailure()
    {
        var result = await sut.ConfirmOperatorEmailAsync("not-a-real-token", null);

        Assert.False(result.IsSuccess);
        Assert.Equal(401, result.StatusCode);
    }

    [Fact]
    public async Task ConfirmOperatorEmailAsync_ValidToken_ConfirmsAndReturnsSuccess()
    {
        var adminUserId = Guid.NewGuid();
        var token = AdminEmailConfirmTokenFactory.CreateToken(ConfirmTokenOptions, adminUserId, "new-op@example.com", TimeSpan.FromHours(48));
        adminRbacProvider.Setup(p => p.ConfirmOperatorEmailAsync(adminUserId, "new-op@example.com", null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminMutationResultModel { Outcome = (int)AdminWriteOutcome.Success, EntityId = adminUserId, Detail = null });

        var result = await sut.ConfirmOperatorEmailAsync(token, null);

        Assert.True(result.IsSuccess);
    }

    [Fact]
    public async Task ConfirmOperatorEmailAsync_ProviderReportsNotFound_ReturnsNotFoundFailure()
    {
        var adminUserId = Guid.NewGuid();
        var token = AdminEmailConfirmTokenFactory.CreateToken(ConfirmTokenOptions, adminUserId, "new-op@example.com", TimeSpan.FromHours(48));
        adminRbacProvider.Setup(p => p.ConfirmOperatorEmailAsync(adminUserId, "new-op@example.com", null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminMutationResultModel { Outcome = (int)AdminWriteOutcome.NotFound, EntityId = null, Detail = "This confirmation link no longer matches an operator on file." });

        var result = await sut.ConfirmOperatorEmailAsync(token, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(404, result.StatusCode);
    }

    /* ------------------------------- GetRecentAuditAsync ------------------------------ */

    [Fact]
    public async Task GetRecentAuditAsync_RequiresAuditReadPermission_AndMapsEntries()
    {
        var (token, _, _) = ArrangeSession(AdminPermissions.AuditRead);
        var entry = new AdminAuditEntryModel
        {
            AuditId = Guid.NewGuid(),
            AdminUserId = Guid.NewGuid(),
            Username = "ops-admin",
            Action = "role.permission.granted",
            EntityType = "role",
            EntityId = Guid.NewGuid().ToString(),
            Summary = "granted content.plans.write",
            CreatedFromIp = "203.0.113.1",
            CreatedAtUtc = DateTime.UtcNow
        };
        adminRbacProvider.Setup(p => p.GetRecentAuditAsync(50, It.IsAny<CancellationToken>())).ReturnsAsync([entry]);

        var result = await sut.GetRecentAuditAsync(token, 50);

        Assert.True(result.IsSuccess);
        var dto = Assert.Single(result.Data!);
        Assert.Equal(entry.AuditId, dto.AuditId);
        Assert.Equal(entry.Summary, dto.Summary);
    }
}
