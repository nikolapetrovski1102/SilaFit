using Moq;
using Silen.Common.Authorization;
using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Common.Helpers;
using Silen.Data.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class AdminConsoleServiceTests
{
    private readonly Mock<IAdminProvider> adminProvider = new(MockBehavior.Strict);
    private readonly Mock<IAdminRbacProvider> adminRbacProvider = new(MockBehavior.Strict);
    private readonly Mock<IAdminContentProvider> contentProvider = new(MockBehavior.Strict);
    private readonly Mock<IMockDataSeeder> mockDataSeeder = new(MockBehavior.Strict);
    private readonly AdminConsoleService sut;

    public AdminConsoleServiceTests()
    {
        sut = new AdminConsoleService(adminProvider.Object, adminRbacProvider.Object, contentProvider.Object, mockDataSeeder.Object);
    }

    private (string SessionToken, Guid AdminUserId) ArrangeSession(params string[] permissions)
    {
        const string sessionToken = "session-token";
        var adminUserId = Guid.NewGuid();
        var session = new AdminSessionModel
        {
            AdminSessionId = Guid.NewGuid(),
            AdminUserId = adminUserId,
            Username = "ops-admin",
            ExpiresAtUtc = DateTime.UtcNow.AddMinutes(30),
            AbsoluteExpiresAtUtc = DateTime.UtcNow.AddHours(8),
            LastSeenAtUtc = DateTime.UtcNow
        };
        adminProvider.Setup(p => p.GetSessionAsync(AdminSessionTokenFactory.HashToken(sessionToken), It.IsAny<CancellationToken>())).ReturnsAsync(session);
        adminRbacProvider.Setup(p => p.GetPermissionsAsync(adminUserId, It.IsAny<CancellationToken>())).ReturnsAsync(permissions.ToList());
        return (sessionToken, adminUserId);
    }

    private static AdminMutationResultModel Success(Guid? id = null) =>
        new() { Outcome = (int)AdminWriteOutcome.Success, EntityId = id ?? Guid.NewGuid(), Detail = null };

    /* -------------------------------- exercises -------------------------------- */

    [Fact]
    public async Task SaveExerciseAsync_BlankName_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.ExercisesWrite);
        var request = new AdminExerciseUpsertRequest { Name = "   ", MuscleGroup = "chest" };

        var result = await sut.SaveExerciseAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveExerciseAsync_UnknownMuscleGroup_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.ExercisesWrite);
        var request = new AdminExerciseUpsertRequest { Name = "Bench Press", MuscleGroup = "glutes" };

        var result = await sut.SaveExerciseAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveExerciseAsync_Valid_TrimsNameBeforeCallingProvider()
    {
        var (token, _) = ArrangeSession(AdminPermissions.ExercisesWrite);
        var request = new AdminExerciseUpsertRequest { Name = "  Bench Press  ", MuscleGroup = "chest" };
        AdminExerciseUpsertRequest? captured = null;
        contentProvider.Setup(p => p.UpsertExerciseAsync(It.IsAny<AdminExerciseUpsertRequest>(), It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .Callback<AdminExerciseUpsertRequest, AdminActorModel, CancellationToken>((req, _, _) => captured = req)
            .ReturnsAsync(Success());

        var result = await sut.SaveExerciseAsync(token, request, null);

        Assert.True(result.IsSuccess);
        Assert.Equal("Bench Press", captured!.Name);
    }

    /* --------------------------- meal suggestions ---------------------------- */

    [Fact]
    public async Task GetMealSuggestionsAsync_OutOfRangeMonth_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SuggestionsRead);

        var result = await sut.GetMealSuggestionsAsync(token, 13, null, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task GetMealSuggestionsAsync_UnknownMealType_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SuggestionsRead);

        var result = await sut.GetMealSuggestionsAsync(token, null, "Brunch", null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveMealSuggestionAsync_BlankTitle_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SuggestionsWrite);
        var request = new AdminMealSuggestionUpsertRequest { Title = " ", MealType = "Breakfast", SuggestedMonth = 1 };

        var result = await sut.SaveMealSuggestionAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveMealSuggestionAsync_UnknownMealType_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SuggestionsWrite);
        var request = new AdminMealSuggestionUpsertRequest { Title = "Oats", MealType = "Brunch", SuggestedMonth = 1 };

        var result = await sut.SaveMealSuggestionAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveMealSuggestionAsync_OutOfRangeMonth_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SuggestionsWrite);
        var request = new AdminMealSuggestionUpsertRequest { Title = "Oats", MealType = "Breakfast", SuggestedMonth = 0 };

        var result = await sut.SaveMealSuggestionAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    /* --------------------------------- plans -------------------------------- */

    [Fact]
    public async Task SavePlanAsync_BlankCodeOrName_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.PlansWrite);
        var request = new AdminPlanUpsertRequest { Code = "  ", Name = "Pro" };

        var result = await sut.SavePlanAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SavePlanAsync_Valid_UppercasesAndTrimsCode()
    {
        var (token, _) = ArrangeSession(AdminPermissions.PlansWrite);
        var request = new AdminPlanUpsertRequest { Code = " pro ", Name = " Pro Plan " };
        AdminPlanUpsertRequest? captured = null;
        contentProvider.Setup(p => p.UpsertPlanAsync(It.IsAny<AdminPlanUpsertRequest>(), It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .Callback<AdminPlanUpsertRequest, AdminActorModel, CancellationToken>((req, _, _) => captured = req)
            .ReturnsAsync(Success());

        var result = await sut.SavePlanAsync(token, request, null);

        Assert.True(result.IsSuccess);
        Assert.Equal("PRO", captured!.Code);
        Assert.Equal("Pro Plan", captured.Name);
    }

    [Fact]
    public async Task SavePlanFeatureAsync_BlankText_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.PlansWrite);
        var request = new AdminPlanFeatureUpsertRequest { PlanId = Guid.NewGuid(), FeatureText = "   " };

        var result = await sut.SavePlanFeatureAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    /* -------------------------------- splits -------------------------------- */

    private static AdminSplitUpsertRequest ValidSplitRequest() => new()
    {
        Name = "Push Pull Legs",
        Category = "PushPullLegs",
        Level = "Beginner",
        DurationDays = 6,
        Visibility = ""
    };

    [Fact]
    public async Task SaveSplitAsync_BlankName_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SplitsWrite);
        var request = ValidSplitRequest();
        request.Name = "  ";

        var result = await sut.SaveSplitAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveSplitAsync_UnknownCategory_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SplitsWrite);
        var request = ValidSplitRequest();
        request.Category = "Arnold";

        var result = await sut.SaveSplitAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveSplitAsync_UnknownLevel_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SplitsWrite);
        var request = ValidSplitRequest();
        request.Level = "Expert";

        var result = await sut.SaveSplitAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveSplitAsync_UnknownRecommendedGoalWhenSet_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SplitsWrite);
        var request = ValidSplitRequest();
        request.RecommendedGoal = "GetShredded";

        var result = await sut.SaveSplitAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveSplitAsync_OutOfRangeDuration_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SplitsWrite);
        var request = ValidSplitRequest();
        request.DurationDays = 15;

        var result = await sut.SaveSplitAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveSplitAsync_BlankVisibility_DefaultsToPrivate()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SplitsWrite);
        var request = ValidSplitRequest();
        request.Visibility = "  ";
        AdminSplitUpsertRequest? captured = null;
        contentProvider.Setup(p => p.UpsertSplitAsync(It.IsAny<AdminSplitUpsertRequest>(), It.IsAny<AdminActorModel>(), false, It.IsAny<CancellationToken>()))
            .Callback<AdminSplitUpsertRequest, AdminActorModel, bool, CancellationToken>((req, _, _, _) => captured = req)
            .ReturnsAsync(Success());

        var result = await sut.SaveSplitAsync(token, request, null);

        Assert.True(result.IsSuccess);
        Assert.Equal("Private", captured!.Visibility);
    }

    [Fact]
    public async Task SaveSplitAsync_UnknownVisibility_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SplitsWrite);
        var request = ValidSplitRequest();
        request.Visibility = "SuperSecret";

        var result = await sut.SaveSplitAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task GetSplitDetailAsync_ProviderReturnsNull_ReturnsNotFoundFailure()
    {
        var (token, adminUserId) = ArrangeSession(AdminPermissions.SplitsRead);
        var splitId = Guid.NewGuid();
        contentProvider.Setup(p => p.GetSplitDetailAsync(splitId, adminUserId, false, It.IsAny<CancellationToken>())).ReturnsAsync((AdminSplitDetailModel?)null);

        var result = await sut.GetSplitDetailAsync(token, splitId);

        Assert.False(result.IsSuccess);
        Assert.Equal(404, result.StatusCode);
    }

    [Fact]
    public async Task GetSplitsAsync_OperatorOwnsSplit_CanManageTrueWithoutManageAllPermission()
    {
        var (token, adminUserId) = ArrangeSession(AdminPermissions.SplitsRead);
        var ownedSplit = new AdminSplitModel { SplitId = Guid.NewGuid(), OwnerAdminUserId = adminUserId };
        contentProvider.Setup(p => p.GetSplitsAsync(adminUserId, false, It.IsAny<CancellationToken>())).ReturnsAsync([ownedSplit]);

        var result = await sut.GetSplitsAsync(token);

        Assert.True(result.IsSuccess);
        Assert.True(result.Data!.Single().CanManage);
    }

    [Fact]
    public async Task GetSplitsAsync_OperatorDoesNotOwnSplit_CanManageFalseWithoutManageAllPermission()
    {
        var (token, adminUserId) = ArrangeSession(AdminPermissions.SplitsRead);
        var othersSplit = new AdminSplitModel { SplitId = Guid.NewGuid(), OwnerAdminUserId = Guid.NewGuid() };
        contentProvider.Setup(p => p.GetSplitsAsync(adminUserId, false, It.IsAny<CancellationToken>())).ReturnsAsync([othersSplit]);

        var result = await sut.GetSplitsAsync(token);

        Assert.True(result.IsSuccess);
        Assert.False(result.Data!.Single().CanManage);
    }

    [Fact]
    public async Task GetSplitsAsync_WithManageAllPermission_CanManageTrueRegardlessOfOwnership()
    {
        var (token, adminUserId) = ArrangeSession(AdminPermissions.SplitsRead, AdminPermissions.SplitsManageAll);
        var othersSplit = new AdminSplitModel { SplitId = Guid.NewGuid(), OwnerAdminUserId = Guid.NewGuid() };
        contentProvider.Setup(p => p.GetSplitsAsync(adminUserId, true, It.IsAny<CancellationToken>())).ReturnsAsync([othersSplit]);

        var result = await sut.GetSplitsAsync(token);

        Assert.True(result.IsSuccess);
        Assert.True(result.Data!.Single().CanManage);
    }

    [Fact]
    public async Task AssignSplitAsync_EmptySplitOrUserId_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SplitsAssign);
        var request = new AdminSplitAssignRequest { SplitId = Guid.Empty, UserId = Guid.NewGuid(), SetActive = true };

        var result = await sut.AssignSplitAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveSplitDayAsync_BlankTitleOnTrainingDay_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SplitsWrite);
        var request = new AdminSplitDayUpsertRequest { SplitId = Guid.NewGuid(), DayIndex = 1, Title = "  ", IsRestDay = false };

        var result = await sut.SaveSplitDayAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveSplitDayAsync_BlankTitleOnRestDay_IsAllowed()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SplitsWrite);
        var request = new AdminSplitDayUpsertRequest { SplitId = Guid.NewGuid(), DayIndex = 3, Title = "  ", IsRestDay = true };
        contentProvider.Setup(p => p.UpsertSplitDayAsync(It.IsAny<AdminSplitDayUpsertRequest>(), It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(Success());

        var result = await sut.SaveSplitDayAsync(token, request, null);

        Assert.True(result.IsSuccess);
        Assert.Equal("Day 3 saved.", result.Data!.Message);
    }

    [Fact]
    public async Task SaveSplitDayAsync_OutOfRangeDayIndex_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SplitsWrite);
        var request = new AdminSplitDayUpsertRequest { SplitId = Guid.NewGuid(), DayIndex = 0, Title = "Push", IsRestDay = false };

        var result = await sut.SaveSplitDayAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveSplitDayExerciseAsync_TargetSetsLessThanOne_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SplitsWrite);
        var request = new AdminSplitDayExerciseUpsertRequest { SplitDayId = Guid.NewGuid(), ExerciseId = Guid.NewGuid(), TargetSets = 0, TargetRepsLow = 8, TargetRepsHigh = 12 };

        var result = await sut.SaveSplitDayExerciseAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SaveSplitDayExerciseAsync_InvertedRepRange_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.SplitsWrite);
        var request = new AdminSplitDayExerciseUpsertRequest { SplitDayId = Guid.NewGuid(), ExerciseId = Guid.NewGuid(), TargetSets = 3, TargetRepsLow = 12, TargetRepsHigh = 8 };

        var result = await sut.SaveSplitDayExerciseAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    /* --------------------------------- users / mock data -------------------------------- */

    [Fact]
    public async Task SeedUserMockDataAsync_EmptyUserId_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.UsersMockData);
        var request = new AdminMockDataRequest { UserId = Guid.Empty };

        var result = await sut.SeedUserMockDataAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SeedUserMockDataAsync_BlankProfile_DefaultsToAdvanced()
    {
        var (token, _) = ArrangeSession(AdminPermissions.UsersMockData);
        var userId = Guid.NewGuid();
        var request = new AdminMockDataRequest { UserId = userId, Profile = "  ", Days = 10 };
        mockDataSeeder.Setup(s => s.SeedUserAsync(userId, MockDataProfiles.Advanced, 10, null, It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new MockDataSeedResult(userId, MockDataProfiles.Advanced, "PPL", 10, 8, 2, 20, 15, 10));

        var result = await sut.SeedUserMockDataAsync(token, request, null);

        Assert.True(result.IsSuccess);
    }

    [Fact]
    public async Task SeedUserMockDataAsync_UnknownProfile_ReturnsValidationFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.UsersMockData);
        var request = new AdminMockDataRequest { UserId = Guid.NewGuid(), Profile = "Elite" };

        var result = await sut.SeedUserMockDataAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task SeedUserMockDataAsync_DaysZeroOrLess_DefaultsToThirty()
    {
        var (token, _) = ArrangeSession(AdminPermissions.UsersMockData);
        var userId = Guid.NewGuid();
        var request = new AdminMockDataRequest { UserId = userId, Profile = MockDataProfiles.Pro, Days = 0 };
        mockDataSeeder.Setup(s => s.SeedUserAsync(userId, MockDataProfiles.Pro, 30, null, It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new MockDataSeedResult(userId, MockDataProfiles.Pro, "Upper/Lower", 30, 20, 10, 60, 30, 15));

        var result = await sut.SeedUserMockDataAsync(token, request, null);

        Assert.True(result.IsSuccess);
    }

    [Fact]
    public async Task SeedUserMockDataAsync_DaysAbove365_ClampsToThreeSixtyFive()
    {
        var (token, _) = ArrangeSession(AdminPermissions.UsersMockData);
        var userId = Guid.NewGuid();
        var request = new AdminMockDataRequest { UserId = userId, Profile = MockDataProfiles.Advanced, Days = 1000 };
        mockDataSeeder.Setup(s => s.SeedUserAsync(userId, MockDataProfiles.Advanced, 365, null, It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new MockDataSeedResult(userId, MockDataProfiles.Advanced, "PPL", 365, 200, 50, 700, 300, 150));

        var result = await sut.SeedUserMockDataAsync(token, request, null);

        Assert.True(result.IsSuccess);
    }

    [Fact]
    public async Task SeedUserMockDataAsync_UnknownUser_ReturnsNotFoundFailure()
    {
        var (token, _) = ArrangeSession(AdminPermissions.UsersMockData);
        var userId = Guid.NewGuid();
        var request = new AdminMockDataRequest { UserId = userId, Profile = MockDataProfiles.Advanced, Days = 30 };
        mockDataSeeder.Setup(s => s.SeedUserAsync(userId, MockDataProfiles.Advanced, 30, null, It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((MockDataSeedResult?)null);

        var result = await sut.SeedUserMockDataAsync(token, request, null);

        Assert.False(result.IsSuccess);
        Assert.Equal(404, result.StatusCode);
    }

    [Fact]
    public async Task SeedUserMockDataAsync_HappyPath_ReturnsFormattedMessage()
    {
        var (token, _) = ArrangeSession(AdminPermissions.UsersMockData);
        var userId = Guid.NewGuid();
        var request = new AdminMockDataRequest { UserId = userId, Profile = MockDataProfiles.Advanced, Days = 30, Seed = 42 };
        mockDataSeeder.Setup(s => s.SeedUserAsync(userId, MockDataProfiles.Advanced, 30, 42, It.IsAny<AdminActorModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new MockDataSeedResult(userId, MockDataProfiles.Advanced, "PPL", 30, 25, 5, 90, 30, 15));

        var result = await sut.SeedUserMockDataAsync(token, request, null);

        Assert.True(result.IsSuccess);
        Assert.Equal(userId, result.Data!.Id);
        Assert.Equal("Generated 30 day(s) of Advanced mock data: 25 workouts, 90 meals logged.", result.Data.Message);
    }
}
