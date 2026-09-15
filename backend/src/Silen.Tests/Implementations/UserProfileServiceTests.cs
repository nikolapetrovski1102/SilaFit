using Moq;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class UserProfileServiceTests
{
    private readonly Mock<IUserProfileProvider> userProfileProvider = new(MockBehavior.Strict);
    private readonly Mock<ISplitService> splitService = new(MockBehavior.Strict);
    private readonly Mock<IMealPlanningService> mealPlanningService = new(MockBehavior.Strict);
    private readonly UserProfileService sut;

    public UserProfileServiceTests()
    {
        sut = new UserProfileService(userProfileProvider.Object, splitService.Object, mealPlanningService.Object);
    }

    private static UpsertUserProfileRequest ValidRequest() => new()
    {
        Gender = "Male",
        AgeYears = 30,
        HeightCm = 180,
        WeightKg = 80,
        Goal = "BuildMuscle",
        TrainingDaysPerWeek = 4,
        SessionDurationMinutes = 60,
        TrainingExperience = "Intermediate",
        EquipmentAccess = "FullGym",
        DailyActivityLevel = "Active"
    };

    private static UserProfileModel Profile(Guid userId) => new()
    {
        UserId = userId,
        Gender = "Male",
        AgeYears = 30,
        HeightCm = 180,
        WeightKg = 80,
        Goal = "BuildMuscle",
        TrainingDaysPerWeek = 4,
        SessionDurationMinutes = 60,
        TrainingExperience = "Intermediate",
        EquipmentAccess = "FullGym",
        DailyActivityLevel = "Active"
    };

    // ---- GetAsync ----

    [Fact]
    public async Task GetAsync_ProfileNotFound_Fails()
    {
        var userId = Guid.NewGuid();
        userProfileProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserProfileModel?)null);

        var result = await sut.GetAsync(userId);

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task GetAsync_ProfileFound_ReturnsIt()
    {
        var userId = Guid.NewGuid();
        var profile = Profile(userId);
        userProfileProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(profile);

        var result = await sut.GetAsync(userId);

        Assert.True(result.IsSuccess);
        Assert.Equal(userId, result.Data!.UserId);
    }

    // ---- UpsertAsync: validation ----

    [Theory]
    [InlineData(0)]
    [InlineData(8)]
    public async Task UpsertAsync_InvalidTrainingDaysPerWeek_Fails(int days)
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        request.TrainingDaysPerWeek = days;

        var result = await sut.UpsertAsync(userId, request);

        Assert.False(result.IsSuccess);
    }

    [Theory]
    [InlineData(10)]
    [InlineData(200)]
    public async Task UpsertAsync_InvalidSessionDuration_Fails(int minutes)
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        request.SessionDurationMinutes = minutes;

        var result = await sut.UpsertAsync(userId, request);

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task UpsertAsync_InvalidTrainingExperience_Fails()
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        request.TrainingExperience = "Expert";

        var result = await sut.UpsertAsync(userId, request);

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task UpsertAsync_InvalidEquipmentAccess_Fails()
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        request.EquipmentAccess = "HomeGym";

        var result = await sut.UpsertAsync(userId, request);

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task UpsertAsync_InvalidDailyActivityLevel_Fails()
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        request.DailyActivityLevel = "SuperActive";

        var result = await sut.UpsertAsync(userId, request);

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task UpsertAsync_InvalidGender_Fails()
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        request.Gender = "Unknown";

        var result = await sut.UpsertAsync(userId, request);

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task UpsertAsync_InvalidGoal_Fails()
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        request.Goal = "GetShredded";

        var result = await sut.UpsertAsync(userId, request);

        Assert.False(result.IsSuccess);
    }

    [Theory]
    [InlineData(12)]
    [InlineData(101)]
    public async Task UpsertAsync_InvalidAge_Fails(int age)
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        request.AgeYears = (byte)age;

        var result = await sut.UpsertAsync(userId, request);

        Assert.False(result.IsSuccess);
    }

    [Theory]
    [InlineData(99)]
    [InlineData(251)]
    public async Task UpsertAsync_InvalidHeight_Fails(int heightCm)
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        request.HeightCm = heightCm;

        var result = await sut.UpsertAsync(userId, request);

        Assert.False(result.IsSuccess);
    }

    [Theory]
    [InlineData(29)]
    [InlineData(301)]
    public async Task UpsertAsync_InvalidWeight_Fails(int weightKg)
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        request.WeightKg = weightKg;

        var result = await sut.UpsertAsync(userId, request);

        Assert.False(result.IsSuccess);
    }

    [Fact]
    public async Task UpsertAsync_ValidationFailure_NeverCallsProviderOrSideEffects()
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        request.Gender = "Unknown";

        var result = await sut.UpsertAsync(userId, request);

        Assert.False(result.IsSuccess);
        userProfileProvider.Verify(p => p.UpsertAsync(It.IsAny<Guid>(), It.IsAny<UpsertUserProfileRequest>(), It.IsAny<CancellationToken>()), Times.Never);
        splitService.Verify(s => s.AutoAssignRecommendedAsync(It.IsAny<Guid>(), It.IsAny<UserProfileModel>(), It.IsAny<CancellationToken>()), Times.Never);
        mealPlanningService.Verify(m => m.RecomputeTargetsAsync(It.IsAny<Guid>(), It.IsAny<UserProfileModel>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    // ---- UpsertAsync: success + side-effect orchestration ----

    [Fact]
    public async Task UpsertAsync_ValidRequest_SavesProfile_AndTriggersSplitAutoAssignAndTargetsRecompute()
    {
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        var savedProfile = Profile(userId);

        userProfileProvider.Setup(p => p.UpsertAsync(userId, request, It.IsAny<CancellationToken>()))
            .ReturnsAsync(savedProfile);
        splitService.Setup(s => s.AutoAssignRecommendedAsync(userId, savedProfile, It.IsAny<CancellationToken>()))
            .ReturnsAsync(ServiceResult<ActiveSplitModel?>.Success(null));
        mealPlanningService.Setup(m => m.RecomputeTargetsAsync(userId, savedProfile, It.IsAny<CancellationToken>()))
            .ReturnsAsync(ServiceResult<UserNutritionTargetsModel>.Success(new UserNutritionTargetsModel { UserId = userId }));

        var result = await sut.UpsertAsync(userId, request);

        Assert.True(result.IsSuccess);
        Assert.Equal(userId, result.Data!.UserId);
        splitService.Verify(s => s.AutoAssignRecommendedAsync(userId, savedProfile, It.IsAny<CancellationToken>()), Times.Once);
        mealPlanningService.Verify(m => m.RecomputeTargetsAsync(userId, savedProfile, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task UpsertAsync_SplitAutoAssignReturnsFailureResult_DoesNotFailProfileSave()
    {
        // AutoAssignRecommendedAsync/RecomputeTargetsAsync report failures via ServiceResult.IsSuccess = false
        // rather than throwing, so a failed side effect must not abort the overall Upsert.
        var userId = Guid.NewGuid();
        var request = ValidRequest();
        var savedProfile = Profile(userId);

        userProfileProvider.Setup(p => p.UpsertAsync(userId, request, It.IsAny<CancellationToken>()))
            .ReturnsAsync(savedProfile);
        splitService.Setup(s => s.AutoAssignRecommendedAsync(userId, savedProfile, It.IsAny<CancellationToken>()))
            .ReturnsAsync(ServiceResult<ActiveSplitModel?>.Failure(500, "Could not assign a split.", "auto-assign blew up"));
        mealPlanningService.Setup(m => m.RecomputeTargetsAsync(userId, savedProfile, It.IsAny<CancellationToken>()))
            .ReturnsAsync(ServiceResult<UserNutritionTargetsModel>.Success(new UserNutritionTargetsModel { UserId = userId }));

        var result = await sut.UpsertAsync(userId, request);

        Assert.True(result.IsSuccess);
        Assert.Equal(userId, result.Data!.UserId);
    }
}
