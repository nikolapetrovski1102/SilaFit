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

    private static UserProfileModel Profile(string? goal, int? trainingDaysPerWeek = null) => new()
    {
        UserId = Guid.NewGuid(),
        Goal = goal,
        HeightCm = 170,
        WeightKg = 70,
        AgeYears = 30,
        TrainingDaysPerWeek = trainingDaysPerWeek
    };

    private static WorkoutSplitModel Split(string name, string? recommendedGoal, bool isSystemDefault = false) => new()
    {
        SplitId = Guid.NewGuid(),
        Name = name,
        Category = "FullBody",
        Level = "Beginner",
        DurationDays = 3,
        RecommendedGoal = recommendedGoal,
        IsSystemDefault = isSystemDefault
    };

    private static ActiveSplitModel Active(Guid splitId, bool isAutoAssigned) => new()
    {
        UserId = Guid.NewGuid(),
        SplitId = splitId,
        ActivatedAtUtc = DateTime.UtcNow,
        IsAutoAssigned = isAutoAssigned
    };

    [Fact]
    public async Task AutoAssignRecommendedAsync_NoActiveSplit_AssignsTopPickAsAutoAssigned()
    {
        var userId = Guid.NewGuid();
        var profile = Profile("BuildMuscle");
        var best = Split("Best", "BuildMuscle", isSystemDefault: true);
        var other = Split("Other", null);

        splitsProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((ActiveSplitModel?)null);
        splitsProvider.Setup(p => p.GetAllAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([other, best]);
        splitsProvider.Setup(p => p.SetActiveAsync(userId, best.SplitId, true, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Active(best.SplitId, isAutoAssigned: true));

        var result = await sut.AutoAssignRecommendedAsync(userId, profile);

        Assert.True(result.IsSuccess);
        Assert.NotNull(result.Data);
        Assert.Equal(best.SplitId, result.Data!.SplitId);
        splitsProvider.Verify(p => p.SetActiveAsync(userId, best.SplitId, true, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task AutoAssignRecommendedAsync_UserPickedSplitActive_IsPermanentNoOp()
    {
        var userId = Guid.NewGuid();
        var profile = Profile("BuildMuscle");
        var userPicked = Active(Guid.NewGuid(), isAutoAssigned: false);

        splitsProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(userPicked);

        var result = await sut.AutoAssignRecommendedAsync(userId, profile);

        Assert.True(result.IsSuccess);
        Assert.Null(result.Data);
        splitsProvider.Verify(p => p.GetAllAsync(It.IsAny<Guid?>(), It.IsAny<CancellationToken>()), Times.Never);
        splitsProvider.Verify(p => p.SetActiveAsync(It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task AutoAssignRecommendedAsync_ForceReassign_OverridesUserPickedSplit()
    {
        var userId = Guid.NewGuid();
        var profile = Profile("BuildMuscle");
        var userPicked = Active(Guid.NewGuid(), isAutoAssigned: false);
        var best = Split("Best", "BuildMuscle", isSystemDefault: true);

        splitsProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(userPicked);
        splitsProvider.Setup(p => p.GetAllAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([best]);
        splitsProvider.Setup(p => p.SetActiveAsync(userId, best.SplitId, true, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Active(best.SplitId, isAutoAssigned: true));

        var result = await sut.AutoAssignRecommendedAsync(userId, profile, forceReassign: true);

        Assert.True(result.IsSuccess);
        Assert.Equal(best.SplitId, result.Data!.SplitId);
        splitsProvider.Verify(p => p.SetActiveAsync(userId, best.SplitId, true, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task AutoAssignRecommendedAsync_AutoAssignedSplitActive_SwitchesWhenABetterRecommendationExists()
    {
        var userId = Guid.NewGuid();
        var profile = Profile("BuildMuscle");
        var current = Split("Current", null);
        var better = Split("Better", "BuildMuscle", isSystemDefault: true);
        var activeCurrent = Active(current.SplitId, isAutoAssigned: true);

        splitsProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(activeCurrent);
        splitsProvider.Setup(p => p.GetAllAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([current, better]);
        splitsProvider.Setup(p => p.SetActiveAsync(userId, better.SplitId, true, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Active(better.SplitId, isAutoAssigned: true));

        var result = await sut.AutoAssignRecommendedAsync(userId, profile);

        Assert.True(result.IsSuccess);
        Assert.Equal(better.SplitId, result.Data!.SplitId);
        splitsProvider.Verify(p => p.SetActiveAsync(userId, better.SplitId, true, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task AutoAssignRecommendedAsync_AutoAssignedSplitAlreadyOptimal_SkipsRedundantWrite()
    {
        var userId = Guid.NewGuid();
        var profile = Profile("BuildMuscle");
        var best = Split("Best", "BuildMuscle", isSystemDefault: true);
        var activeBest = Active(best.SplitId, isAutoAssigned: true);

        splitsProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(activeBest);
        splitsProvider.Setup(p => p.GetAllAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([best]);

        var result = await sut.AutoAssignRecommendedAsync(userId, profile);

        Assert.True(result.IsSuccess);
        Assert.Null(result.Data);
        splitsProvider.Verify(p => p.SetActiveAsync(It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task AutoAssignRecommendedAsync_ProfileHasNoGoal_IsNoOp()
    {
        var userId = Guid.NewGuid();
        var profile = Profile(goal: null);

        splitsProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((ActiveSplitModel?)null);

        var result = await sut.AutoAssignRecommendedAsync(userId, profile);

        Assert.True(result.IsSuccess);
        Assert.Null(result.Data);
        splitsProvider.Verify(p => p.GetAllAsync(It.IsAny<Guid?>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task AutoAssignRecommendedAsync_ProfileHasTrainingDays_SkipsOverScheduleSplit()
    {
        var userId = Guid.NewGuid();
        var profile = Profile("BuildMuscle", trainingDaysPerWeek: 2);
        var twoDay = Split("2-Day Maintenance", "MaintainActive", isSystemDefault: true);
        twoDay.DurationDays = 2;
        var fourDay = Split("PHUL Power Hypertrophy", "BuildMuscle", isSystemDefault: true);
        fourDay.DurationDays = 4;
        fourDay.Category = "PHUL";
        fourDay.Level = "Intermediate";

        splitsProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((ActiveSplitModel?)null);
        splitsProvider.Setup(p => p.GetAllAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([fourDay, twoDay]);
        splitsProvider.Setup(p => p.SetActiveAsync(userId, twoDay.SplitId, true, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Active(twoDay.SplitId, isAutoAssigned: true));

        var result = await sut.AutoAssignRecommendedAsync(userId, profile);

        Assert.True(result.IsSuccess);
        Assert.Equal(twoDay.SplitId, result.Data!.SplitId);
        splitsProvider.Verify(p => p.SetActiveAsync(userId, twoDay.SplitId, true, It.IsAny<CancellationToken>()), Times.Once);
    }

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
}
