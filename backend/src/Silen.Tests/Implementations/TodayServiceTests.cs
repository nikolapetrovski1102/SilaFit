using Moq;
using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class TodayServiceTests
{
    private readonly Mock<IWorkoutSessionProvider> workoutSessionProvider = new(MockBehavior.Strict);
    private readonly Mock<IHydrationProvider> hydrationProvider = new(MockBehavior.Strict);
    private readonly Mock<IBodyweightProvider> bodyweightProvider = new(MockBehavior.Strict);
    private readonly Mock<IStreakProvider> streakProvider = new(MockBehavior.Strict);
    private readonly Mock<IUserSettingsProvider> userSettingsProvider = new(MockBehavior.Strict);
    private readonly Mock<ISplitsProvider> splitsProvider = new(MockBehavior.Strict);
    private readonly TodayService sut;

    public TodayServiceTests()
    {
        sut = new TodayService(
            workoutSessionProvider.Object,
            hydrationProvider.Object,
            bodyweightProvider.Object,
            streakProvider.Object,
            userSettingsProvider.Object,
            splitsProvider.Object);
    }

    [Fact]
    public async Task GetDashboardAsync_ComposesAllProvidersIntoDashboard()
    {
        var userId = Guid.NewGuid();
        var sessionId = Guid.NewGuid();
        var exerciseId = Guid.NewGuid();
        var splitId = Guid.NewGuid();

        var session = new TodaySessionModel
        {
            WorkoutSessionId = sessionId,
            Status = "Scheduled",
            Title = "Push Day",
            FocusLabel = "Chest/Triceps",
            EstimatedMinutes = 60,
            IsRestDay = false
        };
        var exercises = new List<TargetExerciseModel>
        {
            new() { ExerciseId = exerciseId, Name = "Bench Press", MuscleGroup = "Chest", TargetSets = 4, TargetRepsLow = 6, TargetRepsHigh = 10 }
        };
        workoutSessionProvider
            .Setup(p => p.GetTodayScheduledAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((session, exercises));

        hydrationProvider.Setup(p => p.GetTodayTotalAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(1500);

        var settings = new UserSettingsModel { UserId = userId, TargetWaterMl = 4000 };
        userSettingsProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(settings);

        var weights = new List<BodyweightEntryModel>
        {
            new() { WeightKg = 80m, LoggedAtUtc = new DateTime(2026, 3, 2) },
            new() { WeightKg = 81m, LoggedAtUtc = new DateTime(2026, 3, 1) }
        };
        bodyweightProvider.Setup(p => p.GetLatestAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(weights);

        var streakStatus = new StreakStatusModel { CurrentStreakDays = 5, WeeklyCompliancePercent = 90 };
        var week = new List<WeekDayStatusModel> { new() { SessionDate = new DateTime(2026, 3, 2), SessionStatus = "Completed" } };
        streakProvider.Setup(p => p.GetStatusAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync((streakStatus, week));

        var activeSplit = new ActiveSplitModel { SplitId = splitId, Name = "PPL", DurationDays = 6, ActivatedAtUtc = new DateTime(2026, 2, 1) };
        splitsProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(activeSplit);

        var result = await sut.GetDashboardAsync(userId);

        Assert.True(result.IsSuccess);
        var dto = result.Data!;
        Assert.Equal(sessionId, dto.Session.WorkoutSessionId);
        Assert.Equal("Push Day", dto.Session.Title);
        Assert.False(dto.Session.IsRestDay);
        Assert.Single(dto.TargetExercises);
        Assert.Equal("Bench Press", dto.TargetExercises[0].Name);
        Assert.Equal(1500, dto.HydrationTotalMl);
        Assert.Equal(4000, dto.HydrationTargetMl);
        Assert.Equal(80m, dto.LatestWeightKg);
        Assert.Equal(-1m, dto.WeightDeltaKg);
        Assert.Equal(5, dto.CurrentStreakDays);
        Assert.Equal(90, dto.WeeklyCompliancePercent);
        Assert.Single(dto.WeekStatuses);
        Assert.NotNull(dto.ActiveSplit);
        Assert.Equal(splitId, dto.ActiveSplit!.SplitId);
        Assert.Equal("PPL", dto.ActiveSplit!.Name);
    }

    [Fact]
    public async Task GetDashboardAsync_MissingOrEmptyUpstreamData_DegradesGracefully()
    {
        var userId = Guid.NewGuid();
        workoutSessionProvider
            .Setup(p => p.GetTodayScheduledAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(((TodaySessionModel?)null, new List<TargetExerciseModel>()));
        hydrationProvider.Setup(p => p.GetTodayTotalAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(0);
        userSettingsProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync((UserSettingsModel?)null);
        bodyweightProvider.Setup(p => p.GetLatestAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(new List<BodyweightEntryModel>());
        streakProvider
            .Setup(p => p.GetStatusAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((new StreakStatusModel(), new List<WeekDayStatusModel>()));
        splitsProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync((ActiveSplitModel?)null);

        var result = await sut.GetDashboardAsync(userId);

        Assert.True(result.IsSuccess);
        var dto = result.Data!;
        Assert.True(dto.Session.IsRestDay);
        Assert.Equal("Scheduled", dto.Session.Status);
        Assert.Null(dto.Session.WorkoutSessionId);
        Assert.Empty(dto.TargetExercises);
        Assert.Equal(3500, dto.HydrationTargetMl);
        Assert.Null(dto.LatestWeightKg);
        Assert.Null(dto.WeightDeltaKg);
        Assert.Null(dto.ActiveSplit);
    }

    [Fact]
    public async Task GetDashboardAsync_OnlyOneBodyweightEntry_LatestPresentButDeltaNull()
    {
        var userId = Guid.NewGuid();
        workoutSessionProvider
            .Setup(p => p.GetTodayScheduledAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(((TodaySessionModel?)null, new List<TargetExerciseModel>()));
        hydrationProvider.Setup(p => p.GetTodayTotalAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(0);
        userSettingsProvider.Setup(p => p.GetAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync((UserSettingsModel?)null);
        bodyweightProvider
            .Setup(p => p.GetLatestAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new List<BodyweightEntryModel> { new() { WeightKg = 77.5m, LoggedAtUtc = DateTime.UtcNow } });
        streakProvider
            .Setup(p => p.GetStatusAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((new StreakStatusModel(), new List<WeekDayStatusModel>()));
        splitsProvider.Setup(p => p.GetActiveAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync((ActiveSplitModel?)null);

        var result = await sut.GetDashboardAsync(userId);

        Assert.True(result.IsSuccess);
        Assert.Equal(77.5m, result.Data!.LatestWeightKg);
        Assert.Null(result.Data!.WeightDeltaKg);
    }

    [Fact]
    public async Task LogHydrationAsync_NonPositiveAmount_ReturnsValidationFailure()
    {
        var userId = Guid.NewGuid();
        var request = new LogHydrationRequest { AmountMl = 0 };

        var result = await sut.LogHydrationAsync(userId, request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task LogHydrationAsync_ValidAmount_ReturnsUpdatedTotal()
    {
        var userId = Guid.NewGuid();
        var request = new LogHydrationRequest { AmountMl = 250 };
        hydrationProvider.Setup(p => p.LogAsync(userId, (short)250, It.IsAny<CancellationToken>())).ReturnsAsync(1750);

        var result = await sut.LogHydrationAsync(userId, request);

        Assert.True(result.IsSuccess);
        Assert.Equal(1750, result.Data);
    }

    [Fact]
    public async Task LogBodyweightAsync_NonPositiveWeight_ReturnsValidationFailure()
    {
        var userId = Guid.NewGuid();
        var request = new LogBodyweightRequest { WeightKg = 0 };

        var result = await sut.LogBodyweightAsync(userId, request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task LogBodyweightAsync_ValidWeight_ReturnsLatestAndDelta()
    {
        var userId = Guid.NewGuid();
        var request = new LogBodyweightRequest { WeightKg = 79m };
        bodyweightProvider
            .Setup(p => p.LogAsync(userId, 79m, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new List<BodyweightEntryModel>
            {
                new() { WeightKg = 79m, LoggedAtUtc = DateTime.UtcNow },
                new() { WeightKg = 80m, LoggedAtUtc = DateTime.UtcNow.AddDays(-3) }
            });

        var result = await sut.LogBodyweightAsync(userId, request);

        Assert.True(result.IsSuccess);
        Assert.Equal(79m, result.Data!.LatestWeightKg);
        Assert.Equal(-1m, result.Data!.DeltaKg);
    }

    [Fact]
    public async Task LogBodyweightAsync_FirstEverEntry_DeltaIsNull()
    {
        var userId = Guid.NewGuid();
        var request = new LogBodyweightRequest { WeightKg = 79m };
        bodyweightProvider
            .Setup(p => p.LogAsync(userId, 79m, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new List<BodyweightEntryModel> { new() { WeightKg = 79m, LoggedAtUtc = DateTime.UtcNow } });

        var result = await sut.LogBodyweightAsync(userId, request);

        Assert.True(result.IsSuccess);
        Assert.Equal(79m, result.Data!.LatestWeightKg);
        Assert.Null(result.Data!.DeltaKg);
    }

    [Fact]
    public async Task CompleteWorkoutAsync_NonPositiveDuration_ReturnsValidationFailure()
    {
        var userId = Guid.NewGuid();
        var request = new CompleteWorkoutRequest { WorkoutSessionId = Guid.NewGuid(), DurationMinutes = 0 };

        var result = await sut.CompleteWorkoutAsync(userId, request);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task CompleteWorkoutAsync_ValidRequest_MapsSetLogsAndReturnsCompletion()
    {
        var userId = Guid.NewGuid();
        var sessionId = Guid.NewGuid();
        var exerciseId = Guid.NewGuid();
        var request = new CompleteWorkoutRequest
        {
            WorkoutSessionId = sessionId,
            DurationMinutes = 45,
            CaloriesEstimate = 300,
            RpeScore = 8m,
            TonnageKg = 2500m,
            SetLogs = new List<SetLogRequest>
            {
                new() { ExerciseId = exerciseId, SetNumber = 1, WeightKg = 100m, Reps = 8 }
            }
        };
        var completion = new WorkoutSessionCompletionModel { WorkoutSessionId = sessionId, Status = "Completed", DurationMinutes = 45 };

        workoutSessionProvider
            .Setup(p => p.CompleteAsync(
                userId, sessionId, 45, (short?)300, 8m, 2500m,
                It.Is<IReadOnlyList<SetLogEntryModel>>(logs => logs.Count == 1 && logs[0].ExerciseId == exerciseId && logs[0].Reps == 8),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(completion);

        var result = await sut.CompleteWorkoutAsync(userId, request);

        Assert.True(result.IsSuccess);
        Assert.Equal(sessionId, result.Data!.WorkoutSessionId);
        Assert.Equal("Completed", result.Data!.Status);
    }

    [Fact]
    public async Task CompleteWorkoutAsync_SessionNotFound_ReturnsNotFoundFailure()
    {
        var userId = Guid.NewGuid();
        var sessionId = Guid.NewGuid();
        var request = new CompleteWorkoutRequest { WorkoutSessionId = sessionId, DurationMinutes = 30 };

        workoutSessionProvider
            .Setup(p => p.CompleteAsync(
                userId, sessionId, 30, (short?)null, null, null,
                null,
                It.IsAny<CancellationToken>()))
            .ReturnsAsync((WorkoutSessionCompletionModel?)null);

        var result = await sut.CompleteWorkoutAsync(userId, request);

        Assert.False(result.IsSuccess);
        Assert.Equal(404, result.StatusCode);
    }
}
