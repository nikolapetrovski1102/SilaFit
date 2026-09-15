using Moq;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class ProgressServiceTests
{
    private readonly Mock<IWorkoutSessionProvider> workoutSessionProvider = new(MockBehavior.Strict);
    private readonly Mock<IStreakProvider> streakProvider = new(MockBehavior.Strict);
    private readonly ProgressService sut;

    public ProgressServiceTests()
    {
        sut = new ProgressService(workoutSessionProvider.Object, streakProvider.Object);
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
}
