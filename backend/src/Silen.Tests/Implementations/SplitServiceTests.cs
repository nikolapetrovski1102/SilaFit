using Moq;
using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class SplitServiceTests
{
    private readonly Mock<ISplitsProvider> splitsProvider = new(MockBehavior.Strict);
    private readonly Mock<IUserProfileProvider> userProfileProvider = new(MockBehavior.Strict);
    private readonly Mock<ISubscriptionGate> subscriptionGate = new(MockBehavior.Strict);
    private readonly SplitService sut;

    public SplitServiceTests()
    {
        sut = new SplitService(splitsProvider.Object, userProfileProvider.Object, subscriptionGate.Object);
    }

    private static ActiveSplitModel Active(Guid splitId, bool isAutoAssigned) => new()
    {
        UserId = Guid.NewGuid(),
        SplitId = splitId,
        ActivatedAtUtc = DateTime.UtcNow,
        IsAutoAssigned = isAutoAssigned
    };

    [Fact]
    public async Task ActivateAsync_AlwaysMarksSplitAsUserPicked_NotAutoAssigned()
    {
        var userId = Guid.NewGuid();
        var request = new ActivateSplitRequest { SplitId = Guid.NewGuid() };
        var activated = Active(request.SplitId, isAutoAssigned: false);

        splitsProvider.Setup(p => p.SetActiveAsync(userId, request.SplitId, false, It.IsAny<CancellationToken>()))
            .ReturnsAsync(activated);

        var result = await sut.ActivateAsync(userId, request);

        Assert.True(result.IsSuccess);
        Assert.False(result.Data!.IsAutoAssigned);
        splitsProvider.Verify(p => p.SetActiveAsync(userId, request.SplitId, false, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task GetAllAsync_Guest_ReturnsProUpgradeRequiredFailure()
    {
        var result = await sut.GetAllAsync(null);

        Assert.False(result.IsSuccess);
        Assert.Equal(403, result.StatusCode);
    }

    [Fact]
    public async Task GetAllAsync_FreeUser_ReturnsProUpgradeRequiredFailure()
    {
        var userId = Guid.NewGuid();
        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(false);

        var result = await sut.GetAllAsync(userId);

        Assert.False(result.IsSuccess);
        Assert.Equal(403, result.StatusCode);
    }

    [Fact]
    public async Task GetAllAsync_ProUser_ReturnsTheLibrary()
    {
        var userId = Guid.NewGuid();
        var split = new WorkoutSplitModel { SplitId = Guid.NewGuid(), Name = "Push Pull Legs", Category = "PushPullLegs", Level = "Intermediate", DurationDays = 6 };
        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(true);
        splitsProvider.Setup(p => p.GetAllAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync([split]);
        userProfileProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync((UserProfileModel?)null);

        var result = await sut.GetAllAsync(userId);

        Assert.True(result.IsSuccess);
        Assert.Equal(split.SplitId, Assert.Single(result.Data!).SplitId);
    }
}
