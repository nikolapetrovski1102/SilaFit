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

    [Fact]
    public async Task DuplicateMySplitAsync_FreeUser_ReturnsUpgradeRequiredWithoutCopying()
    {
        var userId = Guid.NewGuid();
        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(false);

        var result = await sut.DuplicateMySplitAsync(userId, Guid.NewGuid());

        Assert.False(result.IsSuccess);
        Assert.Equal(403, result.StatusCode);
        splitsProvider.Verify(p => p.DuplicateUserSplitAsync(It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task DuplicateMySplitAsync_ProUserAtSplitLimit_ReturnsPlanLimitWithoutCopying()
    {
        var userId = Guid.NewGuid();
        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(true);
        subscriptionGate.Setup(g => g.GetEntitlementsAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PlanEntitlementsModel { MaxActiveSplits = 2 });
        splitsProvider.Setup(p => p.GetOwnedSplitsAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([new WorkoutSplitModel(), new WorkoutSplitModel()]);

        var result = await sut.DuplicateMySplitAsync(userId, Guid.NewGuid());

        Assert.False(result.IsSuccess);
        Assert.Equal(403, result.StatusCode);
        splitsProvider.Verify(p => p.DuplicateUserSplitAsync(It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task DuplicateMySplitAsync_ProUserUnderLimit_ReturnsCopyId()
    {
        var userId = Guid.NewGuid();
        var splitId = Guid.NewGuid();
        var copyId = Guid.NewGuid();
        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(true);
        subscriptionGate.Setup(g => g.GetEntitlementsAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PlanEntitlementsModel { MaxActiveSplits = null });
        splitsProvider.Setup(p => p.DuplicateUserSplitAsync(splitId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminMutationResultModel { Outcome = 0, EntityId = copyId });

        var result = await sut.DuplicateMySplitAsync(userId, splitId);

        Assert.True(result.IsSuccess);
        Assert.Equal(copyId, result.Data!.Id);
    }

    [Fact]
    public async Task DuplicateMySplitDayAsync_FreeUser_IsAllowed()
    {
        var userId = Guid.NewGuid();
        var splitDayId = Guid.NewGuid();
        var newDayId = Guid.NewGuid();
        splitsProvider.Setup(p => p.DuplicateUserSplitDayAsync(splitDayId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new AdminMutationResultModel { Outcome = 0, EntityId = newDayId });

        var result = await sut.DuplicateMySplitDayAsync(userId, splitDayId);

        Assert.True(result.IsSuccess);
        Assert.Equal(newDayId, result.Data!.Id);
    }
}
