using Moq;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
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
    private readonly Mock<IMealPlanningService> mealPlanningService = new(MockBehavior.Strict);
    private readonly DietPlanService sut;

    public DietPlanServiceTests()
    {
        sut = new DietPlanService(provider.Object, subscriptionGate.Object, mealPlanningService.Object);
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
    public async Task GetDetailAsync_AggregatesCompatibleIngredientQuantities()
    {
        var planId = Guid.NewGuid();
        provider
            .Setup(p => p.GetDetailAsync(planId, null, It.IsAny<CancellationToken>()))
            .ReturnsAsync((
                Plan(planId),
                new List<DietPlanDayModel> { new() { DietPlanDayId = Guid.NewGuid(), DayIndex = 1 } },
                new List<DietPlanMealModel>(),
                new List<string> { "2 eggs", "1 cup oats", "4 eggs", " 1 cup oats ", "1 banana" }));

        var result = await sut.GetDetailAsync(planId, null);

        Assert.True(result.IsSuccess);
        Assert.Equal(new[] { "Eggs ×6", "Oats ×2 cups", "Banana ×1" }, result.Data!.ShoppingList);
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
        // Detail()'s plan has no meals, so there's nothing to apply -
        // the strict mock would throw if this were called unexpectedly.
        mealPlanningService.Verify(
            m => m.ApplyPlannedMealsAsync(It.IsAny<Guid>(), It.IsAny<List<UpsertMealLogRequest>>(), It.IsAny<CancellationToken>()),
            Times.Never);
    }

    [Fact]
    public async Task ActivateAsync_PlanWithMeals_AppliesThemToTheUpcomingWeek()
    {
        var userId = Guid.NewGuid();
        var planId = Guid.NewGuid();
        var days = Enumerable.Range(1, 7)
            .Select(i => new DietPlanDayModel { DietPlanDayId = Guid.NewGuid(), DayIndex = (byte)i })
            .ToList();
        var meals = days
            .Select(d => new DietPlanMealModel
            {
                DietPlanDayId = d.DietPlanDayId,
                DietPlanMealId = Guid.NewGuid(),
                MealType = "Breakfast",
                Title = $"Meal for day {d.DayIndex}",
                CaloriesKcal = 400
            })
            .ToList();

        provider
            .Setup(p => p.GetDetailAsync(planId, userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((Plan(planId), days, meals, new List<string>()));
        provider
            .Setup(p => p.SetActiveDietPlanAsync(userId, planId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        List<UpsertMealLogRequest>? captured = null;
        mealPlanningService
            .Setup(m => m.ApplyPlannedMealsAsync(userId, It.IsAny<List<UpsertMealLogRequest>>(), It.IsAny<CancellationToken>()))
            .Callback<Guid, List<UpsertMealLogRequest>, CancellationToken>((_, requests, _) => captured = requests)
            .ReturnsAsync(ServiceResult<int>.Success(7));

        var result = await sut.ActivateAsync(userId, planId);

        Assert.True(result.IsSuccess);
        Assert.NotNull(captured);
        // One meal per upcoming day: a 7-day plan maps 1:1 onto each of the
        // next 7 calendar dates regardless of which weekday "today" is.
        Assert.Equal(7, captured!.Count);
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        Assert.Equal(
            Enumerable.Range(0, 7).Select(today.AddDays),
            captured.Select(r => r.LogDateUtc));
        Assert.All(captured, r => Assert.Equal("Planned", r.Status));
    }
}
