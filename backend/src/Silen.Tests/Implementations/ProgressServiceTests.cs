using Moq;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class ProgressServiceTests
{
    private readonly Mock<IWorkoutSessionProvider> workoutSessionProvider = new(MockBehavior.Strict);
    private readonly Mock<IStreakProvider> streakProvider = new(MockBehavior.Strict);
    private readonly Mock<ISubscriptionGate> subscriptionGate = new(MockBehavior.Strict);
    private readonly ProgressService sut;

    public ProgressServiceTests()
    {
        sut = new ProgressService(workoutSessionProvider.Object, streakProvider.Object, subscriptionGate.Object);
    }

    [Fact]
    public async Task GetOverviewAsync_NonPositiveDays_DefaultsToA30DayRangeEndingToday()
    {
        var userId = Guid.NewGuid();
        DateTime capturedFrom = default;
        DateTime capturedTo = default;

        workoutSessionProvider
            .Setup(p => p.GetRangeSummaryAsync(userId, It.IsAny<DateTime>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Callback<Guid, DateTime, DateTime, CancellationToken>((_, from, to, _) =>
            {
                capturedFrom = from;
                capturedTo = to;
            })
            .ReturnsAsync((new RangeSummaryModel(), new List<DaySessionStatusModel>()));
        streakProvider
            .Setup(p => p.GetStatusAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((new StreakStatusModel(), new List<WeekDayStatusModel>()));

        var result = await sut.GetOverviewAsync(userId, 0);

        Assert.True(result.IsSuccess);
        Assert.Equal(DateTime.UtcNow.Date, capturedTo);
        Assert.Equal(29, (capturedTo - capturedFrom).Days);
    }

    [Fact]
    public async Task GetOverviewAsync_PositiveDays_UsesRequestedRangeLength()
    {
        var userId = Guid.NewGuid();
        DateTime capturedFrom = default;
        DateTime capturedTo = default;

        workoutSessionProvider
            .Setup(p => p.GetRangeSummaryAsync(userId, It.IsAny<DateTime>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Callback<Guid, DateTime, DateTime, CancellationToken>((_, from, to, _) =>
            {
                capturedFrom = from;
                capturedTo = to;
            })
            .ReturnsAsync((new RangeSummaryModel(), new List<DaySessionStatusModel>()));
        streakProvider
            .Setup(p => p.GetStatusAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((new StreakStatusModel(), new List<WeekDayStatusModel>()));

        var result = await sut.GetOverviewAsync(userId, 7);

        Assert.True(result.IsSuccess);
        Assert.Equal(6, (capturedTo - capturedFrom).Days);
    }

    [Fact]
    public async Task GetOverviewAsync_ComposesSummaryStreakAndHeatmapIntoDto()
    {
        var userId = Guid.NewGuid();
        var summary = new RangeSummaryModel
        {
            CompletedSessions = 4,
            ScheduledSessions = 5,
            TotalTonnageKg = 1000m,
            AvgRpe = 7.5m
        };
        var days = new List<DaySessionStatusModel>
        {
            new() { ScheduledDateUtc = new DateTime(2026, 1, 1), Status = "Completed", TonnageKg = 500m, RpeScore = 8m },
            new() { ScheduledDateUtc = new DateTime(2026, 1, 2), Status = "Missed", TonnageKg = null, RpeScore = null }
        };
        var streak = new StreakStatusModel { CurrentStreakDays = 3, WeeklyCompliancePercent = 80 };

        workoutSessionProvider
            .Setup(p => p.GetRangeSummaryAsync(userId, It.IsAny<DateTime>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((summary, days));
        streakProvider
            .Setup(p => p.GetStatusAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((streak, new List<WeekDayStatusModel>()));

        var result = await sut.GetOverviewAsync(userId, 7);

        Assert.True(result.IsSuccess);
        var dto = result.Data!;
        Assert.Equal(3, dto.CurrentStreakDays);
        Assert.Equal(80, dto.WeeklyCompliancePercent);
        Assert.Equal(4, dto.CompletedSessions);
        Assert.Equal(5, dto.ScheduledSessions);
        Assert.Equal(1000m, dto.TotalTonnageKg);
        Assert.Equal(7.5m, dto.AvgRpe);
        Assert.Equal(2, dto.Heatmap.Count);
        Assert.Equal("Completed", dto.Heatmap[0].Status);
        Assert.Equal(500m, dto.Heatmap[0].TonnageKg);
        Assert.Equal("Missed", dto.Heatmap[1].Status);
        Assert.Null(dto.Heatmap[1].TonnageKg);
        Assert.NotEmpty(dto.Insights);
    }

    [Fact]
    public async Task GetPersonalRecordsAsync_NonPositiveTop_DefaultsTo5()
    {
        var userId = Guid.NewGuid();
        int? capturedTop = null;

        workoutSessionProvider
            .Setup(p => p.GetPersonalRecordsAsync(userId, It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .Callback<Guid, int, CancellationToken>((_, top, _) => capturedTop = top)
            .ReturnsAsync(new List<PersonalRecordModel>());

        var result = await sut.GetPersonalRecordsAsync(userId, 0);

        Assert.True(result.IsSuccess);
        Assert.Equal(5, capturedTop);
    }

    [Fact]
    public async Task GetPersonalRecordsAsync_MapsProviderRecordsToDtos()
    {
        var userId = Guid.NewGuid();
        var exerciseId = Guid.NewGuid();
        var records = new List<PersonalRecordModel>
        {
            new()
            {
                ExerciseId = exerciseId,
                ExerciseName = "Bench Press",
                WeightKg = 100m,
                Reps = 5,
                AchievedAtUtc = new DateTime(2026, 1, 1),
                PreviousBestWeightKg = 95m
            }
        };

        workoutSessionProvider
            .Setup(p => p.GetPersonalRecordsAsync(userId, 10, It.IsAny<CancellationToken>()))
            .ReturnsAsync(records);

        var result = await sut.GetPersonalRecordsAsync(userId, 10);

        Assert.True(result.IsSuccess);
        Assert.Single(result.Data!);
        Assert.Equal(exerciseId, result.Data![0].ExerciseId);
        Assert.Equal("Bench Press", result.Data![0].ExerciseName);
        Assert.Equal(100m, result.Data![0].WeightKg);
        Assert.Equal((short)5, result.Data![0].Reps);
        Assert.Equal(95m, result.Data![0].PreviousBestWeightKg);
    }

    [Fact]
    public async Task GetTrackedExercisesAsync_FreeUser_ReturnsProUpgradeRequiredFailure()
    {
        var userId = Guid.NewGuid();
        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(false);

        var result = await sut.GetTrackedExercisesAsync(userId);

        Assert.False(result.IsSuccess);
        Assert.Equal(403, result.StatusCode);
    }

    [Fact]
    public async Task GetTrackedExercisesAsync_ProUser_MapsEveryTrackedExercise()
    {
        var userId = Guid.NewGuid();
        var exerciseId = Guid.NewGuid();
        var lastTrained = new DateTime(2026, 9, 20, 18, 0, 0, DateTimeKind.Utc);
        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(true);
        workoutSessionProvider
            .Setup(p => p.GetTrackedExercisesAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([new TrackedExerciseModel { ExerciseId = exerciseId, ExerciseName = "Bench Press", SessionCount = 6, LastTrainedAtUtc = lastTrained }]);

        var result = await sut.GetTrackedExercisesAsync(userId);

        Assert.True(result.IsSuccess);
        var exercise = Assert.Single(result.Data!);
        Assert.Equal(exerciseId, exercise.ExerciseId);
        Assert.Equal("Bench Press", exercise.ExerciseName);
        Assert.Equal(6, exercise.SessionCount);
        Assert.Equal(lastTrained, exercise.LastTrainedAtUtc);
    }

    [Fact]
    public async Task GetExerciseProgressAsync_FreeUser_ReturnsProUpgradeRequiredFailure()
    {
        var userId = Guid.NewGuid();
        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(false);

        var result = await sut.GetExerciseProgressAsync(userId, Guid.NewGuid(), 90);

        Assert.False(result.IsSuccess);
        Assert.Equal(403, result.StatusCode);
    }

    [Theory]
    [InlineData(0, 90)]
    [InlineData(30, 30)]
    [InlineData(5000, 730)]
    public async Task GetExerciseProgressAsync_ProUser_ClampsRangeAndMapsPoints(int requestedDays, int expectedDays)
    {
        var userId = Guid.NewGuid();
        var exerciseId = Guid.NewGuid();
        DateTime capturedFrom = default;
        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(true);
        workoutSessionProvider
            .Setup(p => p.GetExerciseProgressAsync(userId, exerciseId, It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Callback<Guid, Guid, DateTime, CancellationToken>((_, _, from, _) => capturedFrom = from)
            .ReturnsAsync([new ExerciseProgressPointModel
            {
                ScheduledDateUtc = new DateTime(2026, 9, 1),
                TopWeightKg = 100m,
                TopSetReps = 5,
                EstimatedOneRmKg = 116.67m,
                TotalVolumeKg = 1500m,
                TotalReps = 15,
                SetCount = 3
            }]);

        var result = await sut.GetExerciseProgressAsync(userId, exerciseId, requestedDays);

        Assert.True(result.IsSuccess);
        Assert.Equal(expectedDays, result.Data!.Days);
        Assert.Equal(expectedDays - 1, (DateTime.UtcNow.Date - capturedFrom).Days);
        var point = Assert.Single(result.Data.Points);
        Assert.Equal(100m, point.TopWeightKg);
        Assert.Equal(5, point.TopSetReps);
        Assert.Equal(116.67m, point.EstimatedOneRmKg);
        Assert.Equal(1500m, point.TotalVolumeKg);
        Assert.Equal(15, point.TotalReps);
        Assert.Equal(3, point.SetCount);
    }
}
