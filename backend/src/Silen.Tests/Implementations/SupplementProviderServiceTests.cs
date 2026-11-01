using Moq;
using Silen.Common.Authorization;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class SupplementProviderServiceTests
{
    private readonly Mock<IAdminProvider> adminProvider = new(MockBehavior.Strict);
    private readonly Mock<IAdminRbacProvider> adminRbacProvider = new(MockBehavior.Strict);
    private readonly Mock<ISupplementProvidersProvider> providersProvider = new(MockBehavior.Strict);
    private readonly Mock<IImageUploadService> imageUploadService = new(MockBehavior.Strict);
    private readonly SupplementProviderService sut;

    public SupplementProviderServiceTests()
    {
        sut = new SupplementProviderService(adminProvider.Object, adminRbacProvider.Object, providersProvider.Object, imageUploadService.Object);
    }

    private string ArrangeSession(params string[] permissions)
    {
        const string sessionToken = "session-token";
        var adminUserId = Guid.NewGuid();
        adminProvider.Setup(p => p.GetSessionAsync(AdminSessionTokenFactory.HashToken(sessionToken), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminSessionModel { AdminUserId = adminUserId, Username = "ops" });
        adminRbacProvider.Setup(p => p.GetPermissionsAsync(adminUserId, It.IsAny<CancellationToken>())).ReturnsAsync(permissions.ToList());
        return sessionToken;
    }

    [Theory]
    [InlineData("http://proteini.si")]
    [InlineData("javascript:alert(1)")]
    [InlineData("proteini.si")]
    public async Task SaveAsync_NonHttpsShopLink_IsRejected(string shopUrl)
    {
        var session = ArrangeSession(AdminPermissions.ProvidersWrite);

        var result = await sut.SaveAsync(session, new AdminSupplementProviderUpsertRequest { Name = "Proteini", ShopUrl = shopUrl }, null);

        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveAsync_Valid_TrimsAndSaves()
    {
        var session = ArrangeSession(AdminPermissions.ProvidersWrite);
        AdminSupplementProviderUpsertRequest? saved = null;
        providersProvider.Setup(p => p.UpsertAsync(It.IsAny<AdminSupplementProviderUpsertRequest>(), It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .Callback<AdminSupplementProviderUpsertRequest, AdminActorModel, CancellationToken>((r, _, _) => saved = r)
            .ReturnsAsync(new AdminMutationResultModel { Outcome = (int)AdminWriteOutcome.Success, EntityId = Guid.NewGuid() });

        var result = await sut.SaveAsync(session,
            new AdminSupplementProviderUpsertRequest { Name = "  Proteini.si  ", ShopUrl = " https://proteini.si/ ", LogoUrl = " " }, null);

        Assert.True(result.IsSuccess);
        Assert.Equal("Proteini.si", saved!.Name);
        Assert.Equal("https://proteini.si/", saved.ShopUrl);
        Assert.Null(saved.LogoUrl);
    }

    [Fact]
    public async Task SaveAsync_ReadOnlyOperator_IsForbidden()
    {
        var session = ArrangeSession(AdminPermissions.ProvidersRead);

        var result = await sut.SaveAsync(session, new AdminSupplementProviderUpsertRequest { Name = "x" }, null);

        Assert.Equal(403, result.StatusCode);
    }

    [Fact]
    public void CleanRecipeLines_DropsBlanks_AndRefusesTooMany()
    {
        Assert.Equal(["a", "b"], AdminConsoleService.CleanRecipeLines([" a ", "", "  ", "b"], 5, 10, "step"));
        Assert.Throws<Silen.Common.Exceptions.ValidationException>(() =>
            AdminConsoleService.CleanRecipeLines(Enumerable.Repeat("x", 6).ToList(), 5, 10, "step"));
    }
}
