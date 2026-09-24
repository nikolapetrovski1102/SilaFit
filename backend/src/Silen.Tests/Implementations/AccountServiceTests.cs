using Moq;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class AccountServiceTests
{
    private readonly Mock<IAccountProvider> accountProvider = new(MockBehavior.Strict);
    private readonly Mock<IEmailSender> emailSender = new(MockBehavior.Strict);
    private readonly Mock<IAppleSignInRevoker> appleSignInRevoker = new(MockBehavior.Strict);
    private readonly AccountService sut;

    public AccountServiceTests()
    {
        sut = new AccountService(accountProvider.Object, emailSender.Object, appleSignInRevoker.Object);
    }

    [Fact]
    public async Task DeleteAsync_RevokesAppleTokenBeforeDeletingTheAccount()
    {
        var userId = Guid.NewGuid();
        var calls = new List<string>();
        appleSignInRevoker.Setup(r => r.RevokeAsync(userId, It.IsAny<CancellationToken>()))
            .Callback(() => calls.Add("revoke"))
            .Returns(Task.CompletedTask);
        accountProvider.Setup(p => p.DeleteAsync(userId, It.IsAny<CancellationToken>()))
            .Callback(() => calls.Add("delete"))
            .Returns(Task.CompletedTask);

        var result = await sut.DeleteAsync(userId);

        Assert.True(result.IsSuccess);
        Assert.Equal(["revoke", "delete"], calls);
    }
}
