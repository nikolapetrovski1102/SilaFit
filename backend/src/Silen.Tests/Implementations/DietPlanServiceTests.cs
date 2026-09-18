using Moq;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class DietPlanServiceTests
{
    private readonly Mock<IDietPlansProvider> provider = new(MockBehavior.Strict);
    private readonly Mock<ISubscriptionGate> subscriptionGate = new(MockBehavior.Strict);
    private readonly DietPlanService sut;

    public DietPlanServiceTests()
    {
        sut = new DietPlanService(provider.Object, subscriptionGate.Object);
    }

    private static DietPlanModel Plan(Guid planId, string name = "Weekly Plan") => new()
    {
        DietPlanId = planId,
        Name = name,
        PeriodType = "Weekly",
        DurationDays = 7
    };

    private static (DietPlanModel? Plan, List<DietPlanDayModel> Days, List<DietPlanMealModel> Meals, List<string> Ingredients)
        Detail(DietPlanModel? plan) =>
        (plan, new List<DietPlanDayModel> { new() { DietPlanDayId = Guid.NewGuid(), DayIndex = 1 } },
            new List<DietPlanMealModel>(), new List<string>());

    [Fact]
    public async Task GetActiveAsync_NoActivePlan_ReturnsSuccessWithNoData()
    {
        var userId = Guid.NewGuid();
        provider
            .Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((ActiveDietPlanModel?)null);

        var result = await sut.GetActiveAsync(userId);

        Assert.True(result.IsSuccess);
        Assert.Null(result.Data);
    }

    [Fact]
    public async Task GetActiveAsync_ActivePlan_ReturnsItsFullDetail()
    {
        var userId = Guid.NewGuid();
        var planId = Guid.NewGuid();
        provider
            .Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ActiveDietPlanModel
            {
                UserId = userId,
                DietPlanId = planId,
                ActivatedAtUtc = DateTime.UtcNow,
                Name = "Weekly Plan",
                DurationDays = 7
            });
        provider
            .Setup(p => p.GetDetailAsync(planId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Detail(Plan(planId)));

        var result = await sut.GetActiveAsync(userId);

        Assert.True(result.IsSuccess);
        Assert.NotNull(result.Data);
        Assert.Equal(planId, result.Data!.Plan.DietPlanId);
        Assert.Single(result.Data.Days);
        // Plan() has no OwnerUserId, so it is not editable by the caller.
        Assert.False(result.Data.Plan.IsEditableByMe);
    }

    [Fact]
    public async Task GetDetailAsync_DeduplicatesShoppingListInFirstSeenOrder()
    {
        var planId = Guid.NewGuid();
        provider
            .Setup(p => p.GetDetailAsync(planId, null, It.IsAny<CancellationToken>()))
            .ReturnsAsync((
                Plan(planId),
                new List<DietPlanDayModel> { new() { DietPlanDayId = Guid.NewGuid(), DayIndex = 1 } },
                new List<DietPlanMealModel>(),
                new List<string> { "2 eggs", "1 cup oats", "2 eggs", " 1 cup oats ", "1 banana" }));

        var result = await sut.GetDetailAsync(planId, null);

        Assert.True(result.IsSuccess);
        Assert.Equal(new[] { "2 eggs", "1 cup oats", "1 banana" }, result.Data!.ShoppingList);
    }

    [Fact]
    public async Task ActivateAsync_InvisiblePlan_FailsNotFound_AndNeverWrites()
    {
        var userId = Guid.NewGuid();
        var planId = Guid.NewGuid();
        provider
            .Setup(p => p.GetDetailAsync(planId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Detail(null));

        var result = await sut.ActivateAsync(userId, planId);

        Assert.False(result.IsSuccess);
        Assert.Equal(404, result.StatusCode);
        provider.Verify(
            p => p.SetActiveDietPlanAsync(It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()),
            Times.Never);
    }

    [Fact]
    public async Task ActivateAsync_VisiblePlan_SetsItActive()
    {
        var userId = Guid.NewGuid();
        var planId = Guid.NewGuid();
        provider
            .Setup(p => p.GetDetailAsync(planId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Detail(Plan(planId)));
        provider
            .Setup(p => p.SetActiveDietPlanAsync(userId, planId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.ActivateAsync(userId, planId);

        Assert.True(result.IsSuccess);
        provider.Verify(
            p => p.SetActiveDietPlanAsync(userId, planId, It.IsAny<CancellationToken>()),
            Times.Once);
    }
}
