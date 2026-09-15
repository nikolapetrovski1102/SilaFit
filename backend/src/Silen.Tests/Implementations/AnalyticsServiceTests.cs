using System.Globalization;
using System.Text.Json;
using Moq;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class AnalyticsServiceTests
{
    private readonly Mock<IAnalyticsProvider> analyticsProvider = new(MockBehavior.Strict);
    private readonly Mock<ISubscriptionGate> subscriptionGate = new(MockBehavior.Strict);
    private readonly Mock<IOpenRouterClient> openRouterClient = new(MockBehavior.Strict);
    private readonly Mock<IAiRefreshThrottle> aiRefreshThrottle = new(MockBehavior.Strict);
    private readonly AnalyticsService sut;

    public AnalyticsServiceTests()
    {
        sut = new AnalyticsService(analyticsProvider.Object, subscriptionGate.Object, openRouterClient.Object, aiRefreshThrottle.Object);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(13)]
    public async Task GetMonthlyAsync_MonthOutOfRange_ReturnsValidationFailure(int month)
    {
        var userId = Guid.NewGuid();

        var result = await sut.GetMonthlyAsync(userId, 2026, month, refresh: false);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task GetMonthlyAsync_UserWithoutProSubscription_ReturnsUpgradeRequiredFailure()
    {
        var userId = Guid.NewGuid();
        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(false);

        var result = await sut.GetMonthlyAsync(userId, 2026, 3, refresh: false);

        Assert.False(result.IsSuccess);
        Assert.Equal(403, result.StatusCode);
    }

    [Fact]
    public async Task GetMonthlyAsync_NotEnoughTrackedActivity_ReturnsInsufficientDataFailure()
    {
        var userId = Guid.NewGuid();
        const int year = 2026;
        const int month = 3;

        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(true);
        analyticsProvider
            .Setup(p => p.GetCachedReportAsync(userId, year, month, It.IsAny<CancellationToken>()))
            .ReturnsAsync((MonthlyAnalyticsReportModel?)null);
        analyticsProvider
            .Setup(p => p.GetPeriodSnapshotAsync(userId, It.IsAny<DateTime>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new MonthlySnapshotModel { CompletedSessions = 1, LoggedMealDays = 1 });

        var result = await sut.GetMonthlyAsync(userId, year, month, refresh: false);

        Assert.False(result.IsSuccess);
        Assert.Equal(422, result.StatusCode);
    }

    [Fact]
    public async Task GetMonthlyAsync_NoCacheAndEnoughActivity_GeneratesAndSavesFreshReport()
    {
        var userId = Guid.NewGuid();
        const int year = 2026;
        const int month = 3;

        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(true);
        analyticsProvider
            .Setup(p => p.GetCachedReportAsync(userId, year, month, It.IsAny<CancellationToken>()))
            .ReturnsAsync((MonthlyAnalyticsReportModel?)null);

        var snapshot = new MonthlySnapshotModel
        {
            CompletedSessions = 3,
            LoggedMealDays = 2,
            DisplayName = "Alex",
            TotalTonnageKg = 5000m,
            AvgRpe = 7m,
            CurrentStreakDays = 4,
            WeeklyCompliancePercent = 75,
            TotalDaysInRange = 31
        };
        analyticsProvider
            .Setup(p => p.GetPeriodSnapshotAsync(
                userId,
                new DateTime(year, month, 1, 0, 0, 0, DateTimeKind.Utc),
                new DateTime(year, month, 31, 0, 0, 0, DateTimeKind.Utc),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(snapshot);

        var template = new AiPromptTemplateModel { TemplateKey = "MonthlyAnalytics", SystemPrompt = "sys", UserPromptTemplate = "Hi {{DisplayName}}" };
        analyticsProvider
            .Setup(p => p.GetPromptTemplateAsync("MonthlyAnalytics", It.IsAny<CancellationToken>()))
            .ReturnsAsync(template);

        const string aiJson = """{"strengths":["Consistent squats"],"improvements":[{"area":"Sleep","recommendation":"Sleep more","priority":"Medium"}],"focusForNextMonth":"Add another leg day"}""";
        openRouterClient
            .Setup(c => c.GenerateJsonAsync("sys", It.IsAny<string>(), It.IsAny<JsonElement>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(aiJson);

        var generatedAt = new DateTime(2026, 3, 15, 0, 0, 0, DateTimeKind.Utc);
        analyticsProvider
            .Setup(p => p.SaveReportAsync(userId, year, month, It.IsAny<string>(), aiJson, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new MonthlyAnalyticsReportModel { GeneratedAtUtc = generatedAt });

        var result = await sut.GetMonthlyAsync(userId, year, month, refresh: false);

        Assert.True(result.IsSuccess);
        var dto = result.Data!;
        Assert.Equal(year, dto.Year);
        Assert.Equal(month, dto.Month);
        Assert.Equal("Add another leg day", dto.FocusForNextMonth);
        Assert.Single(dto.Strengths);
        Assert.Single(dto.Improvements);
        Assert.Equal(generatedAt, dto.GeneratedAtUtc);
        Assert.Equal(5000m, dto.Summary.TotalTonnageKg);
        Assert.Equal(4, dto.Summary.CurrentStreakDays);
    }

    [Fact]
    public async Task GetMonthlyAsync_ValidCacheForCurrentMonth_ReturnsCachedReportWithoutCallingAi()
    {
        var userId = Guid.NewGuid();
        var today = DateTime.UtcNow.Date;

        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(true);

        var cachedSnapshot = new MonthlySnapshotModel
        {
            RealDataOnly = true,
            RecapVersion = 2,
            CompletedSessions = 10,
            LoggedMealDays = 10,
            TotalTonnageKg = 9999m
        };
        analyticsProvider
            .Setup(p => p.GetCachedReportAsync(userId, today.Year, today.Month, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new MonthlyAnalyticsReportModel
            {
                SnapshotJson = JsonSerializer.Serialize(cachedSnapshot),
                ResultJson = """{"strengths":["Cached win"],"improvements":[],"focusForNextMonth":"Cached focus"}""",
                GeneratedAtUtc = today.AddDays(-1)
            });

        var result = await sut.GetMonthlyAsync(userId, null, null, refresh: false);

        Assert.True(result.IsSuccess);
        Assert.Equal("Cached focus", result.Data!.FocusForNextMonth);
        Assert.Equal(9999m, result.Data!.Summary.TotalTonnageKg);
    }

    [Fact]
    public async Task GetMonthlyAsync_RefreshRequestedButThrottled_FallsBackToCachedReport()
    {
        var userId = Guid.NewGuid();
        var today = DateTime.UtcNow.Date;

        subscriptionGate.Setup(g => g.HasActiveProAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(true);
        aiRefreshThrottle.Setup(t => t.TryAcquire(userId, "Monthly", TimeSpan.FromDays(30))).Returns(false);

        var cachedSnapshot = new MonthlySnapshotModel { RealDataOnly = true, RecapVersion = 2, CompletedSessions = 10, LoggedMealDays = 10 };
        analyticsProvider
            .Setup(p => p.GetCachedReportAsync(userId, today.Year, today.Month, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new MonthlyAnalyticsReportModel
            {
                SnapshotJson = JsonSerializer.Serialize(cachedSnapshot),
                ResultJson = """{"strengths":[],"improvements":[],"focusForNextMonth":"Still cached"}""",
                GeneratedAtUtc = today
            });

        var result = await sut.GetMonthlyAsync(userId, null, null, refresh: true);

        Assert.True(result.IsSuccess);
        Assert.Equal("Still cached", result.Data!.FocusForNextMonth);
        aiRefreshThrottle.Verify(t => t.TryAcquire(userId, "Monthly", TimeSpan.FromDays(30)), Times.Once);
    }

    [Fact]
    public async Task GetWeeklyAsync_WeekOutOfRange_ReturnsValidationFailure()
    {
        var userId = Guid.NewGuid();

        var result = await sut.GetWeeklyAsync(userId, 2026, 60, refresh: false);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task GetWeeklyAsync_UserWithoutAdvancedSubscription_ReturnsUpgradeRequiredFailure()
    {
        var userId = Guid.NewGuid();
        subscriptionGate.Setup(g => g.HasActiveAdvancedAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(false);

        var result = await sut.GetWeeklyAsync(userId, 2026, 10, refresh: false);

        Assert.False(result.IsSuccess);
        Assert.Equal(403, result.StatusCode);
    }

    [Fact]
    public async Task GetWeeklyAsync_NotEnoughTrackedActivity_ReturnsInsufficientDataFailure()
    {
        var userId = Guid.NewGuid();
        const int year = 2026;
        const int week = 10;

        subscriptionGate.Setup(g => g.HasActiveAdvancedAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(true);
        analyticsProvider
            .Setup(p => p.GetCachedWeeklyReportAsync(userId, year, week, It.IsAny<CancellationToken>()))
            .ReturnsAsync((WeeklyAnalyticsReportModel?)null);
        analyticsProvider
            .Setup(p => p.GetPeriodSnapshotAsync(userId, It.IsAny<DateTime>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new MonthlySnapshotModel { CompletedSessions = 0, LoggedMealDays = 1 });

        var result = await sut.GetWeeklyAsync(userId, year, week, refresh: false);

        Assert.False(result.IsSuccess);
        Assert.Equal(422, result.StatusCode);
    }

    [Fact]
    public async Task GetWeeklyAsync_NoCacheAndEnoughActivity_GeneratesAndSavesFreshReport()
    {
        var userId = Guid.NewGuid();
        const int year = 2026;
        const int week = 10;
        var weekStart = DateTime.SpecifyKind(ISOWeek.ToDateTime(year, week, DayOfWeek.Monday), DateTimeKind.Utc);
        var weekEnd = weekStart.AddDays(6);

        subscriptionGate.Setup(g => g.HasActiveAdvancedAsync(userId, It.IsAny<CancellationToken>())).ReturnsAsync(true);
        analyticsProvider
            .Setup(p => p.GetCachedWeeklyReportAsync(userId, year, week, It.IsAny<CancellationToken>()))
            .ReturnsAsync((WeeklyAnalyticsReportModel?)null);

        var snapshot = new MonthlySnapshotModel { CompletedSessions = 2, LoggedMealDays = 1, TotalTonnageKg = 1234m };
        analyticsProvider
            .Setup(p => p.GetPeriodSnapshotAsync(userId, weekStart, weekEnd, It.IsAny<CancellationToken>()))
            .ReturnsAsync(snapshot);

        var template = new AiPromptTemplateModel { TemplateKey = "WeeklyAnalytics", SystemPrompt = "wsys", UserPromptTemplate = "Hi" };
        analyticsProvider
            .Setup(p => p.GetPromptTemplateAsync("WeeklyAnalytics", It.IsAny<CancellationToken>()))
            .ReturnsAsync(template);

        const string aiJson = """{"strengths":["Nice week"],"improvements":[],"focusForNextWeek":"Add mobility work"}""";
        openRouterClient
            .Setup(c => c.GenerateJsonAsync("wsys", It.IsAny<string>(), It.IsAny<JsonElement>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(aiJson);

        var generatedAt = weekEnd.AddDays(1);
        analyticsProvider
            .Setup(p => p.SaveWeeklyReportAsync(userId, year, week, It.IsAny<string>(), aiJson, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new WeeklyAnalyticsReportModel { GeneratedAtUtc = generatedAt });

        var result = await sut.GetWeeklyAsync(userId, year, week, refresh: false);

        Assert.True(result.IsSuccess);
        var dto = result.Data!;
        Assert.Equal("Add mobility work", dto.FocusForNextWeek);
        Assert.Equal(year, dto.Year);
        Assert.Equal(week, dto.WeekNumber);
        Assert.Equal(weekStart, dto.WeekStartUtc);
        Assert.Equal(weekEnd, dto.WeekEndUtc);
        Assert.Equal(generatedAt, dto.GeneratedAtUtc);
    }
}
