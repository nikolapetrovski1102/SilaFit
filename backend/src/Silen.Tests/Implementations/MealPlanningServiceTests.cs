using Moq;
using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class MealPlanningServiceTests
{
    private readonly Mock<IMealPlanningProvider> mealPlanningProvider = new(MockBehavior.Strict);
    private readonly Mock<IUserProfileProvider> userProfileProvider = new(MockBehavior.Strict);
    private readonly MealPlanningService sut;

    public MealPlanningServiceTests()
    {
        sut = new MealPlanningService(mealPlanningProvider.Object, userProfileProvider.Object);
    }

    private static UserProfileModel Profile(
        string gender, byte age, decimal heightCm, decimal weightKg, string goal, string? activity = null,
        int? trainingDays = null, int? sessionMinutes = null) => new()
    {
        UserId = Guid.NewGuid(),
        Gender = gender,
        AgeYears = age,
        HeightCm = heightCm,
        WeightKg = weightKg,
        Goal = goal,
        DailyActivityLevel = activity,
        TrainingDaysPerWeek = trainingDays,
        SessionDurationMinutes = sessionMinutes
    };

    /// <summary>Captures whatever request MealPlanningService derives so the test can
    /// assert on the exact Mifflin-St Jeor arithmetic without duplicating it.</summary>
    private UpsertNutritionTargetsRequest CaptureUpsertedTargets(Guid userId)
    {
        UpsertNutritionTargetsRequest? captured = null;
        mealPlanningProvider
            .Setup(p => p.GetTargetsAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserNutritionTargetsModel?)null);
        mealPlanningProvider
            .Setup(p => p.UpsertTargetsAsync(userId, It.IsAny<UpsertNutritionTargetsRequest>(), It.IsAny<CancellationToken>()))
            .Callback<Guid, UpsertNutritionTargetsRequest, CancellationToken>((_, request, _) => captured = request)
            .ReturnsAsync((Guid _, UpsertNutritionTargetsRequest request, CancellationToken _) => new UserNutritionTargetsModel
            {
                UserId = userId,
                TargetCalories = request.TargetCalories,
                TargetProteinG = request.TargetProteinG,
                TargetCarbsG = request.TargetCarbsG,
                TargetFatsG = request.TargetFatsG,
                IsManualOverride = request.IsManualOverride
            });

        return captured!;
    }

    [Fact]
    public async Task GetTargetsAsync_BuildMuscleMaleProfile_MatchesMifflinStJeorArithmetic()
    {
        var userId = Guid.NewGuid();
        var profile = Profile("Male", 25, 180, 80, "BuildMuscle", "Active");
        userProfileProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(profile);
        CaptureUpsertedTargets(userId);

        var result = await sut.GetTargetsAsync(userId);

        Assert.True(result.IsSuccess);
        // bmr = 10*80 + 6.25*180 - 5*25 + 5 = 1805; tdee = 1805*1.55 = 2797.75;
        // +250 surplus = 3047.75 -> rounds to 3048.
        Assert.Equal(3048, result.Data!.TargetCalories);
        Assert.Equal(160, result.Data.TargetProteinG);
        Assert.Equal(411, result.Data.TargetCarbsG);
        Assert.Equal(85, result.Data.TargetFatsG);
        Assert.False(result.Data.IsManualOverride);
    }

    [Fact]
    public async Task GetTargetsAsync_LoseFatFemaleProfile_MatchesMifflinStJeorArithmetic()
    {
        var userId = Guid.NewGuid();
        var profile = Profile("Female", 30, 165, 65, "LoseFat");
        userProfileProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(profile);
        CaptureUpsertedTargets(userId);

        var result = await sut.GetTargetsAsync(userId);

        // bmr = 650 + 1031.25 - 150 - 161 = 1370.25; tdee (default 1.55, no
        // activity answer) = 2123.8875; -500 deficit = 1623.8875 -> 1624.
        Assert.Equal(1624, result.Data!.TargetCalories);
        Assert.Equal(130, result.Data.TargetProteinG);
        Assert.Equal(175, result.Data.TargetCarbsG);
        Assert.Equal(45, result.Data.TargetFatsG);
    }

    [Fact]
    public async Task GetTargetsAsync_NoProfile_UsesFlatFallbackTargets()
    {
        var userId = Guid.NewGuid();
        userProfileProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync((UserProfileModel?)null);
        CaptureUpsertedTargets(userId);

        var result = await sut.GetTargetsAsync(userId);

        Assert.Equal(2200, result.Data!.TargetCalories);
        Assert.Equal(150, result.Data.TargetProteinG);
        Assert.Equal(220, result.Data.TargetCarbsG);
        Assert.Equal(70, result.Data.TargetFatsG);
    }

    [Fact]
    public async Task GetTargetsAsync_IncompleteProfile_UsesFlatFallbackTargets()
    {
        var userId = Guid.NewGuid();
        // Gender missing - ComputeInitialTargets requires all five fields.
        var profile = Profile("Male", 30, 180, 80, "BuildMuscle");
        profile.Gender = null;
        userProfileProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(profile);
        CaptureUpsertedTargets(userId);

        var result = await sut.GetTargetsAsync(userId);

        Assert.Equal(2200, result.Data!.TargetCalories);
    }

    [Fact]
    public async Task GetTargetsAsync_ExtremeLowEnergyProfile_ClampsToCalorieFloor()
    {
        var userId = Guid.NewGuid();
        var profile = Profile("Female", 18, 150, 40, "LoseFat", "Sedentary");
        userProfileProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(profile);
        CaptureUpsertedTargets(userId);

        var result = await sut.GetTargetsAsync(userId);

        // Raw target computes to ~804 kcal, well under the 1200 kcal safety floor.
        Assert.Equal(1200, result.Data!.TargetCalories);
    }

    [Fact]
    public async Task GetTargetsAsync_ExtremeHighEnergyProfile_ClampsToCalorieCeiling()
    {
        var userId = Guid.NewGuid();
        var profile = Profile("Male", 25, 200, 250, "BuildMuscle", "VeryActive");
        userProfileProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(profile);
        CaptureUpsertedTargets(userId);

        var result = await sut.GetTargetsAsync(userId);

        // Raw target computes to ~6512 kcal, above the 6000 kcal safety ceiling.
        Assert.Equal(6000, result.Data!.TargetCalories);
    }

    [Fact]
    public async Task GetTargetsAsync_MoreTrainingDaysPerWeek_RaisesCalorieTarget()
    {
        // Same height/weight/age/goal/daily-activity: only the onboarding active-day
        // answer differs, so the calorie target must differ too.
        var lowUserId = Guid.NewGuid();
        var low = Profile("Male", 25, 180, 80, "MaintainActive", "Active",
            trainingDays: 2, sessionMinutes: 45);
        userProfileProvider.Setup(p => p.GetAsync(lowUserId, It.IsAny<CancellationToken>())).ReturnsAsync(low);
        CaptureUpsertedTargets(lowUserId);

        var highUserId = Guid.NewGuid();
        var high = Profile("Male", 25, 180, 80, "MaintainActive", "Active",
            trainingDays: 6, sessionMinutes: 45);
        userProfileProvider.Setup(p => p.GetAsync(highUserId, It.IsAny<CancellationToken>())).ReturnsAsync(high);
        CaptureUpsertedTargets(highUserId);

        var lowResult = await sut.GetTargetsAsync(lowUserId);
        var highResult = await sut.GetTargetsAsync(highUserId);

        // bmr = 1805; tdee (Active 1.55) = 2797.75; training = days*45*8.4/7 kcal/day.
        // 2 days -> +108 -> 2906; 6 days -> +324 -> 3122.
        Assert.Equal(2906, lowResult.Data!.TargetCalories);
        Assert.Equal(3122, highResult.Data!.TargetCalories);
    }

    [Fact]
    public async Task GetTargetsAsync_MissingTrainingAnswers_LeavesTdeeUnchanged()
    {
        // Legacy profile with no training-days/session answers must compute exactly
        // as before the training contribution existed.
        var userId = Guid.NewGuid();
        var profile = Profile("Male", 25, 180, 80, "BuildMuscle", "Active");
        userProfileProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(profile);
        CaptureUpsertedTargets(userId);

        var result = await sut.GetTargetsAsync(userId);

        Assert.Equal(3048, result.Data!.TargetCalories);
    }

    [Fact]
    public async Task RecomputeTargetsAsync_ManualOverrideExists_IsNoOp()
    {
        var userId = Guid.NewGuid();
        var profile = Profile("Male", 25, 180, 80, "BuildMuscle");
        var manual = new UserNutritionTargetsModel
        {
            UserId = userId,
            TargetCalories = 2500,
            TargetProteinG = 180,
            TargetCarbsG = 250,
            TargetFatsG = 70,
            IsManualOverride = true
        };
        mealPlanningProvider.Setup(p => p.GetTargetsAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(manual);

        var result = await sut.RecomputeTargetsAsync(userId, profile);

        Assert.True(result.IsSuccess);
        Assert.Same(manual, result.Data);
        mealPlanningProvider.Verify(
            p => p.UpsertTargetsAsync(It.IsAny<Guid>(), It.IsAny<UpsertNutritionTargetsRequest>(), It.IsAny<CancellationToken>()),
            Times.Never);
    }

    [Fact]
    public async Task RecomputeTargetsAsync_NoManualOverride_RecomputesFromProfile()
    {
        var userId = Guid.NewGuid();
        var profile = Profile("Male", 25, 180, 80, "BuildMuscle", "Active");
        var autoExisting = new UserNutritionTargetsModel { UserId = userId, IsManualOverride = false };
        mealPlanningProvider.Setup(p => p.GetTargetsAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(autoExisting);
        mealPlanningProvider
            .Setup(p => p.UpsertTargetsAsync(userId, It.Is<UpsertNutritionTargetsRequest>(r => !r.IsManualOverride), It.IsAny<CancellationToken>()))
            .ReturnsAsync((Guid _, UpsertNutritionTargetsRequest request, CancellationToken _) => new UserNutritionTargetsModel
            {
                UserId = userId,
                TargetCalories = request.TargetCalories
            });

        var result = await sut.RecomputeTargetsAsync(userId, profile);

        Assert.True(result.IsSuccess);
        Assert.Equal(3048, result.Data!.TargetCalories);
    }

    [Fact]
    public async Task UpdateTargetsAsync_PinsManualOverride()
    {
        var userId = Guid.NewGuid();
        var request = new UpsertNutritionTargetsRequest { TargetCalories = 2000, TargetProteinG = 150, TargetCarbsG = 200, TargetFatsG = 60 };
        mealPlanningProvider
            .Setup(p => p.UpsertTargetsAsync(userId, It.Is<UpsertNutritionTargetsRequest>(r => r.IsManualOverride), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new UserNutritionTargetsModel { UserId = userId, TargetCalories = 2000, IsManualOverride = true });

        var result = await sut.UpdateTargetsAsync(userId, request);

        Assert.True(result.IsSuccess);
        Assert.True(result.Data!.IsManualOverride);
    }

    [Fact]
    public async Task UpdateTargetsAsync_NonPositiveCalories_Fails()
    {
        var userId = Guid.NewGuid();
        var request = new UpsertNutritionTargetsRequest { TargetCalories = 0, TargetProteinG = 150, TargetCarbsG = 200, TargetFatsG = 60 };

        var result = await sut.UpdateTargetsAsync(userId, request);

        Assert.False(result.IsSuccess);
        mealPlanningProvider.Verify(
            p => p.UpsertTargetsAsync(It.IsAny<Guid>(), It.IsAny<UpsertNutritionTargetsRequest>(), It.IsAny<CancellationToken>()),
            Times.Never);
    }

    [Fact]
    public async Task GetSuggestionsAsync_PassesUsersTargetsAndGoal_IntoScoring()
    {
        var userId = Guid.NewGuid();
        var profile = Profile("Male", 25, 180, 80, "LoseFat");
        var existingTargets = new UserNutritionTargetsModel { UserId = userId, TargetCalories = 1800, TargetProteinG = 140, IsManualOverride = true };
        var lightMeal = new MealSuggestionModel { MealSuggestionId = Guid.NewGuid(), Title = "Salad", MealType = "Lunch", CaloriesKcal = 400, ProteinG = 35 };
        var heavyMeal = new MealSuggestionModel { MealSuggestionId = Guid.NewGuid(), Title = "Burger", MealType = "Lunch", CaloriesKcal = 900, ProteinG = 35 };

        mealPlanningProvider.Setup(p => p.GetTargetsAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(existingTargets);
        mealPlanningProvider.Setup(p => p.GetSuggestionsForMonthAsync(It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync([heavyMeal, lightMeal]);
        userProfileProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(profile);

        var result = await sut.GetSuggestionsAsync(userId, month: 6);

        Assert.True(result.IsSuccess);
        // LoseFat goal nudge favors the lighter, under-target meal.
        Assert.Equal(lightMeal.MealSuggestionId, result.Data![0].MealSuggestionId);
    }

    [Fact]
    public async Task GetSuggestionsAsync_InvalidMonth_Fails()
    {
        var userId = Guid.NewGuid();

        var result = await sut.GetSuggestionsAsync(userId, month: 13);

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task UpsertMealAsync_WithItems_TotalsComeFromTheFoods_NotTheClient()
    {
        var userId = Guid.NewGuid();
        var request = new UpsertMealLogRequest
        {
            LogDateUtc = new DateOnly(2026, 9, 23),
            MealType = "Lunch",
            Title = "Chicken bowl",
            Status = "Logged",
            CaloriesKcal = 9999,
            Items =
            [
                new MealLogItemModel { Name = " Chicken breast ", Grams = 150, CaloriesKcal = 247.5m, ProteinG = 46.5m, CarbsG = 0, FatsG = 5.4m },
                new MealLogItemModel { Name = "White rice", Grams = 200, CaloriesKcal = 260m, ProteinG = 5.4m, CarbsG = 56.2m, FatsG = 0.6m, FiberG = 0.8m }
            ]
        };
        UpsertMealLogRequest? captured = null;
        mealPlanningProvider
            .Setup(p => p.UpsertMealAsync(userId, It.IsAny<UpsertMealLogRequest>(), It.IsAny<CancellationToken>()))
            .Callback<Guid, UpsertMealLogRequest, CancellationToken>((_, r, _) => captured = r)
            .ReturnsAsync(new MealLogModel());

        var result = await sut.UpsertMealAsync(userId, request);

        Assert.True(result.IsSuccess);
        Assert.NotNull(captured);
        Assert.Equal(508, captured!.CaloriesKcal);
        Assert.Equal(52, captured.ProteinG);
        Assert.Equal(56, captured.CarbsG);
        Assert.Equal(6, captured.FatsG);
        Assert.Equal("Chicken breast", captured.Items![0].Name);
    }

    [Theory]
    [InlineData("", 100, 10)]
    [InlineData("Rice", 0, 10)]
    [InlineData("Rice", 100, -1)]
    public async Task UpsertMealAsync_InvalidItem_FailsValidation_AndNeverWrites(string name, decimal grams, decimal kcal)
    {
        var request = new UpsertMealLogRequest
        {
            LogDateUtc = new DateOnly(2026, 9, 23),
            MealType = "Lunch",
            Title = "Lunch",
            Status = "Logged",
            Items = [new MealLogItemModel { Name = name, Grams = grams, CaloriesKcal = kcal }]
        };

        var result = await sut.UpsertMealAsync(Guid.NewGuid(), request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }
}
