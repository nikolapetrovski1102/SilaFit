using Microsoft.Extensions.Options;
using Moq;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class MonthlyReviewServiceTests
{
    private readonly Mock<IPlansProvider> plansProvider = new(MockBehavior.Strict);
    private readonly Mock<IAnalyticsService> analyticsService = new(MockBehavior.Strict);
    private readonly Mock<IAnalyticsProvider> analyticsProvider = new(MockBehavior.Strict);
    private readonly Mock<IEmailSender> emailSender = new(MockBehavior.Strict);
    private readonly Mock<IMonthlyReviewProvider> monthlyReviewProvider = new(MockBehavior.Strict);

    private static MonthlyReviewOptions ReviewOptions(bool sendEmails = true, string planCode = "ADVANCED") => new()
    {
        SendEmails = sendEmails,
        PlanCode = planCode
    };

    private static SmtpOptions Smtp(string host = "smtp.example.com") => new() { Host = host };

    private static PlanSubscriberModel Subscriber(Guid? userId = null, string? email = "user@example.com", string? displayName = "Jane") => new()
    {
        UserId = userId ?? Guid.NewGuid(),
        Email = email,
        DisplayName = displayName,
        PlanCode = "ADVANCED"
    };

    private static MonthlyAnalyticsDto Report() => new()
    {
        Year = 2026,
        Month = 8,
        GeneratedAtUtc = DateTime.UtcNow,
        Summary = new MonthlyAnalyticsSummaryDto()
    };

    private MonthlyReviewService BuildSut(MonthlyReviewOptions reviewOptions, SmtpOptions smtpOptions) =>
        new(plansProvider.Object, analyticsService.Object, analyticsProvider.Object, emailSender.Object, monthlyReviewProvider.Object,
            Options.Create(reviewOptions), Options.Create(smtpOptions));

    /// <summary>Wires the run scaffold (StartRun/GetSubscribers/GetEmailedIds/CompleteRun) common to every
    /// non-validation-failure test, so each test only has to set up the per-subscriber behaviour it cares about.</summary>
    private (MonthlyReviewService Sut, Guid RunId) Arrange(
        MonthlyReviewOptions reviewOptions,
        SmtpOptions smtpOptions,
        List<PlanSubscriberModel> subscribers,
        HashSet<Guid>? alreadyEmailed = null)
    {
        var runId = Guid.NewGuid();
        monthlyReviewProvider
            .Setup(p => p.StartRunAsync(It.IsAny<int>(), It.IsAny<int>(), reviewOptions.PlanCode, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new MonthlyReviewRunModel { RunId = runId });
        plansProvider
            .Setup(p => p.GetActiveSubscribersByPlanCodeAsync(reviewOptions.PlanCode, It.IsAny<CancellationToken>()))
            .ReturnsAsync(subscribers);
        monthlyReviewProvider
            .Setup(p => p.GetEmailedUserIdsAsync(It.IsAny<int>(), It.IsAny<int>(), It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(alreadyEmailed ?? []);
        monthlyReviewProvider
            .Setup(p => p.CompleteRunAsync(runId, "Completed", subscribers.Count, It.IsAny<int>(), It.IsAny<int>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        return (BuildSut(reviewOptions, smtpOptions), runId);
    }

    [Fact]
    public async Task RunAsync_InvalidMonth_ReturnsValidationFailureWithoutStartingRun()
    {
        var sut = BuildSut(ReviewOptions(), Smtp());

        var result = await sut.RunAsync(2026, 13, null, dryRun: false);

        Assert.False(result.IsSuccess);
        Assert.Equal(400, result.StatusCode);
    }

    [Fact]
    public async Task RunAsync_SubscriberAlreadyEmailedThisPeriod_IsSkippedWithoutRecordingDelivery()
    {
        var reviewOptions = ReviewOptions();
        var subscriber = Subscriber();
        var (sut, _) = Arrange(reviewOptions, Smtp(), [subscriber], alreadyEmailed: [subscriber.UserId]);

        var result = await sut.RunAsync(2026, 8, null, dryRun: false);

        Assert.True(result.IsSuccess);
        Assert.Equal(1, result.Data!.Skipped);
        monthlyReviewProvider.Verify(p => p.RecordDeliveryAsync(It.IsAny<MonthlyReviewDeliveryModel>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task RunAsync_SubscriberWithNoEmailOnFile_IsSkippedAndRecorded()
    {
        var reviewOptions = ReviewOptions();
        var subscriber = Subscriber(email: null);
        var (sut, runId) = Arrange(reviewOptions, Smtp(), [subscriber]);
        monthlyReviewProvider
            .Setup(p => p.RecordDeliveryAsync(
                It.Is<MonthlyReviewDeliveryModel>(d => d.RunId == runId && d.UserId == subscriber.UserId && d.Status == "Skipped"),
                It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RunAsync(2026, 8, null, dryRun: false);

        Assert.Equal(1, result.Data!.Skipped);
        Assert.Equal(0, result.Data.ReportsGenerated);
    }

    [Fact]
    public async Task RunAsync_InsufficientAnalyticsData_IsSkippedNotFailed()
    {
        var reviewOptions = ReviewOptions();
        var subscriber = Subscriber();
        var (sut, _) = Arrange(reviewOptions, Smtp(), [subscriber]);
        analyticsService
            .Setup(a => a.GetMonthlyAsync(subscriber.UserId, 2026, 8, false, It.IsAny<CancellationToken>()))
            .ReturnsAsync(ServiceResult<MonthlyAnalyticsDto>.Failure(InsufficientAnalyticsDataException.HttpStatusCode, "Not enough data.", "insufficient"));
        monthlyReviewProvider
            .Setup(p => p.RecordDeliveryAsync(It.Is<MonthlyReviewDeliveryModel>(d => d.Status == "Skipped" && d.UserId == subscriber.UserId), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RunAsync(2026, 8, null, dryRun: false);

        Assert.Equal(1, result.Data!.Skipped);
        Assert.Equal(0, result.Data.Failures);
    }

    [Fact]
    public async Task RunAsync_GenericAnalyticsFailure_CountsAsFailureWithDetails()
    {
        var reviewOptions = ReviewOptions();
        var subscriber = Subscriber();
        var (sut, _) = Arrange(reviewOptions, Smtp(), [subscriber]);
        analyticsService
            .Setup(a => a.GetMonthlyAsync(subscriber.UserId, 2026, 8, false, It.IsAny<CancellationToken>()))
            .ReturnsAsync(ServiceResult<MonthlyAnalyticsDto>.Failure(500, "Something went wrong", "boom"));
        monthlyReviewProvider
            .Setup(p => p.RecordDeliveryAsync(It.Is<MonthlyReviewDeliveryModel>(d => d.Status == "Failed" && d.ErrorMessage == "boom"), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RunAsync(2026, 8, null, dryRun: false);

        Assert.Equal(1, result.Data!.Failures);
        Assert.Single(result.Data.FailureDetails);
        Assert.Equal("boom", result.Data.FailureDetails[0].Message);
    }

    [Fact]
    public async Task RunAsync_SendEmailsFalse_GeneratesReportWithoutSendingEmail()
    {
        var reviewOptions = ReviewOptions(sendEmails: false);
        var subscriber = Subscriber();
        var (sut, _) = Arrange(reviewOptions, Smtp(), [subscriber]);
        analyticsService
            .Setup(a => a.GetMonthlyAsync(subscriber.UserId, 2026, 8, false, It.IsAny<CancellationToken>()))
            .ReturnsAsync(ServiceResult<MonthlyAnalyticsDto>.Success(Report()));
        monthlyReviewProvider
            .Setup(p => p.RecordDeliveryAsync(It.Is<MonthlyReviewDeliveryModel>(d => d.Status == "Generated" && d.EmailedAtUtc == null), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RunAsync(2026, 8, null, dryRun: false);

        Assert.Equal(1, result.Data!.ReportsGenerated);
        Assert.Equal(0, result.Data.EmailsSent);
        Assert.False(result.Data.EmailsEnabled);
    }

    [Fact]
    public async Task RunAsync_DryRun_DoesNotSendEmailEvenWhenSmtpConfigured()
    {
        var reviewOptions = ReviewOptions();
        var subscriber = Subscriber();
        var (sut, _) = Arrange(reviewOptions, Smtp(), [subscriber]);
        analyticsService
            .Setup(a => a.GetMonthlyAsync(subscriber.UserId, 2026, 8, false, It.IsAny<CancellationToken>()))
            .ReturnsAsync(ServiceResult<MonthlyAnalyticsDto>.Success(Report()));
        monthlyReviewProvider
            .Setup(p => p.RecordDeliveryAsync(It.Is<MonthlyReviewDeliveryModel>(d => d.Status == "Generated"), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RunAsync(2026, 8, null, dryRun: true);

        Assert.False(result.Data!.EmailsEnabled);
        Assert.Equal(1, result.Data.ReportsGenerated);
        Assert.Equal(0, result.Data.EmailsSent);
    }

    [Fact]
    public async Task RunAsync_SmtpHostNotConfigured_EmailsDisabledEvenWhenSendEmailsTrue()
    {
        var reviewOptions = ReviewOptions(sendEmails: true);
        var subscriber = Subscriber();
        var (sut, _) = Arrange(reviewOptions, Smtp(host: ""), [subscriber]);
        analyticsService
            .Setup(a => a.GetMonthlyAsync(subscriber.UserId, 2026, 8, false, It.IsAny<CancellationToken>()))
            .ReturnsAsync(ServiceResult<MonthlyAnalyticsDto>.Success(Report()));
        monthlyReviewProvider
            .Setup(p => p.RecordDeliveryAsync(It.IsAny<MonthlyReviewDeliveryModel>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RunAsync(2026, 8, null, dryRun: false);

        Assert.False(result.Data!.EmailsEnabled);
    }

    [Fact]
    public async Task RunAsync_EmailsEnabled_SendsEmailAndRecordsEmailedDelivery()
    {
        var reviewOptions = ReviewOptions();
        var subscriber = Subscriber();
        var (sut, _) = Arrange(reviewOptions, Smtp(), [subscriber]);
        analyticsService
            .Setup(a => a.GetMonthlyAsync(subscriber.UserId, 2026, 8, false, It.IsAny<CancellationToken>()))
            .ReturnsAsync(ServiceResult<MonthlyAnalyticsDto>.Success(Report()));
        emailSender
            .Setup(e => e.SendAsync(subscriber.Email!, It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        monthlyReviewProvider
            .Setup(p => p.RecordDeliveryAsync(It.Is<MonthlyReviewDeliveryModel>(d => d.Status == "Emailed" && d.EmailedAtUtc != null), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RunAsync(2026, 8, null, dryRun: false);

        Assert.Equal(1, result.Data!.EmailsSent);
        Assert.True(result.Data.EmailsEnabled);
    }

    [Fact]
    public async Task RunAsync_EmailSendThrows_CountsAsFailureAndRecordsError()
    {
        var reviewOptions = ReviewOptions();
        var subscriber = Subscriber();
        var (sut, _) = Arrange(reviewOptions, Smtp(), [subscriber]);
        analyticsService
            .Setup(a => a.GetMonthlyAsync(subscriber.UserId, 2026, 8, false, It.IsAny<CancellationToken>()))
            .ReturnsAsync(ServiceResult<MonthlyAnalyticsDto>.Success(Report()));
        emailSender
            .Setup(e => e.SendAsync(subscriber.Email!, It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("smtp down"));
        monthlyReviewProvider
            .Setup(p => p.RecordDeliveryAsync(It.Is<MonthlyReviewDeliveryModel>(d => d.Status == "Failed" && d.ErrorMessage == "smtp down"), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RunAsync(2026, 8, null, dryRun: false);

        Assert.Equal(1, result.Data!.Failures);
        Assert.Equal(0, result.Data.EmailsSent);
    }

    [Fact]
    public async Task RunAsync_RecordDeliveryThrows_IsSwallowedAndRunStillCompletes()
    {
        var reviewOptions = ReviewOptions(sendEmails: false);
        var subscriber = Subscriber();
        var (sut, runId) = Arrange(reviewOptions, Smtp(), [subscriber]);
        analyticsService
            .Setup(a => a.GetMonthlyAsync(subscriber.UserId, 2026, 8, false, It.IsAny<CancellationToken>()))
            .ReturnsAsync(ServiceResult<MonthlyAnalyticsDto>.Success(Report()));
        monthlyReviewProvider
            .Setup(p => p.RecordDeliveryAsync(It.IsAny<MonthlyReviewDeliveryModel>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new TimeoutException("audit db timeout"));

        var result = await sut.RunAsync(2026, 8, null, dryRun: false);

        Assert.True(result.IsSuccess);
        Assert.Equal(1, result.Data!.ReportsGenerated);
        monthlyReviewProvider.Verify(p => p.CompleteRunAsync(runId, "Completed", 1, 1, 0, 0, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task RunAsync_PlanCodeArgument_OverridesConfiguredDefault()
    {
        var reviewOptions = ReviewOptions(planCode: "ADVANCED");
        var runId = Guid.NewGuid();
        monthlyReviewProvider
            .Setup(p => p.StartRunAsync(2026, 8, "PRO", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new MonthlyReviewRunModel { RunId = runId });
        plansProvider
            .Setup(p => p.GetActiveSubscribersByPlanCodeAsync("PRO", It.IsAny<CancellationToken>()))
            .ReturnsAsync([]);
        monthlyReviewProvider
            .Setup(p => p.GetEmailedUserIdsAsync(2026, 8, It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync([]);
        monthlyReviewProvider
            .Setup(p => p.CompleteRunAsync(runId, "Completed", 0, 0, 0, 0, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        var sut = BuildSut(reviewOptions, Smtp());

        var result = await sut.RunAsync(2026, 8, "PRO", dryRun: false);

        Assert.Equal("PRO", result.Data!.PlanCode);
    }

    [Fact]
    public async Task RunAsync_YearAndMonthOmitted_DefaultsToPreviousUtcCalendarMonth()
    {
        var today = DateTime.UtcNow.Date;
        var expected = new DateTime(today.Year, today.Month, 1, 0, 0, 0, DateTimeKind.Utc).AddMonths(-1);
        var reviewOptions = ReviewOptions();
        var runId = Guid.NewGuid();
        monthlyReviewProvider
            .Setup(p => p.StartRunAsync(expected.Year, expected.Month, reviewOptions.PlanCode, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new MonthlyReviewRunModel { RunId = runId });
        plansProvider
            .Setup(p => p.GetActiveSubscribersByPlanCodeAsync(reviewOptions.PlanCode, It.IsAny<CancellationToken>()))
            .ReturnsAsync([]);
        monthlyReviewProvider
            .Setup(p => p.GetEmailedUserIdsAsync(expected.Year, expected.Month, It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync([]);
        monthlyReviewProvider
            .Setup(p => p.CompleteRunAsync(runId, "Completed", 0, 0, 0, 0, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        var sut = BuildSut(reviewOptions, Smtp());

        var result = await sut.RunAsync(null, null, null, dryRun: false);

        Assert.Equal(expected.Year, result.Data!.Year);
        Assert.Equal(expected.Month, result.Data.Month);
    }

    // -------------------------------------------------------------------------
    // Non-paying (upsell) pass
    // -------------------------------------------------------------------------

    private static PlanSubscriberModel FreeUser(
        Guid? userId = null, string? email = "free@example.com", string? displayName = "Free") => new()
    {
        UserId = userId ?? Guid.NewGuid(),
        Email = email,
        DisplayName = displayName,
        PlanCode = "FREE"
    };

    private static MonthlySnapshotModel Snapshot(int completedSessions = 5, int loggedMealDays = 3) => new()
    {
        CompletedSessions = completedSessions,
        ScheduledSessions = 12,
        LoggedMealDays = loggedMealDays,
        TotalDaysInRange = 31,
        CurrentStreakDays = 4,
        TotalTonnageKg = 12345.6m
    };

    private (MonthlyReviewService Sut, Guid RunId) ArrangeUpsell(
        MonthlyReviewOptions reviewOptions,
        SmtpOptions smtpOptions,
        List<PlanSubscriberModel> nonSubscribers,
        HashSet<Guid>? alreadyEmailed = null)
    {
        var runId = Guid.NewGuid();
        monthlyReviewProvider
            .Setup(p => p.StartRunAsync(It.IsAny<int>(), It.IsAny<int>(), reviewOptions.UpsellAudienceCode, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new MonthlyReviewRunModel { RunId = runId });
        plansProvider
            .Setup(p => p.GetNonSubscribersAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(nonSubscribers);
        monthlyReviewProvider
            .Setup(p => p.GetEmailedUserIdsAsync(It.IsAny<int>(), It.IsAny<int>(), MonthlyReviewDeliveryKinds.Upsell, It.IsAny<CancellationToken>()))
            .ReturnsAsync(alreadyEmailed ?? []);
        monthlyReviewProvider
            .Setup(p => p.CompleteRunAsync(runId, "Completed", nonSubscribers.Count, It.IsAny<int>(), It.IsAny<int>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        return (BuildSut(reviewOptions, smtpOptions), runId);
    }

    [Fact]
    public async Task RunUpsellAsync_NonSubscriberWithActivity_SendsTeaserAndRecordsUpsellDelivery()
    {
        var reviewOptions = ReviewOptions();
        var user = FreeUser();
        var (sut, _) = ArrangeUpsell(reviewOptions, Smtp(), [user]);
        analyticsProvider
            .Setup(a => a.GetPeriodSnapshotAsync(user.UserId, It.IsAny<DateTime>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(Snapshot());
        emailSender
            .Setup(e => e.SendAsync(user.Email!, It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        monthlyReviewProvider
            .Setup(p => p.RecordDeliveryAsync(
                It.Is<MonthlyReviewDeliveryModel>(d =>
                    d.Status == "Emailed" && d.DeliveryKind == MonthlyReviewDeliveryKinds.Upsell && d.EmailedAtUtc != null),
                It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RunUpsellAsync(2026, 8, dryRun: false);

        Assert.True(result.IsSuccess);
        Assert.Equal(MonthlyReviewAudiences.NonSubscribers, result.Data!.Audience);
        Assert.Equal(1, result.Data.UsersConsidered);
        Assert.Equal(1, result.Data.ReportsGenerated);
        Assert.Equal(1, result.Data.EmailsSent);
        Assert.Equal(0, result.Data.Failures);
    }

    [Fact]
    public async Task RunUpsellAsync_NoLoggedActivity_IsSkippedAndRecorded()
    {
        var reviewOptions = ReviewOptions();
        var user = FreeUser();
        var (sut, _) = ArrangeUpsell(reviewOptions, Smtp(), [user]);
        analyticsProvider
            .Setup(a => a.GetPeriodSnapshotAsync(user.UserId, It.IsAny<DateTime>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(Snapshot(completedSessions: 0, loggedMealDays: 0));
        monthlyReviewProvider
            .Setup(p => p.RecordDeliveryAsync(
                It.Is<MonthlyReviewDeliveryModel>(d => d.Status == "Skipped" && d.DeliveryKind == MonthlyReviewDeliveryKinds.Upsell),
                It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RunUpsellAsync(2026, 8, dryRun: false);

        Assert.Equal(1, result.Data!.Skipped);
        Assert.Equal(0, result.Data.EmailsSent);
        Assert.Equal(0, result.Data.ReportsGenerated);
        emailSender.Verify(e => e.SendAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task RunUpsellAsync_AlreadyEmailedThisPeriod_IsSkippedWithoutRecordingDelivery()
    {
        var reviewOptions = ReviewOptions();
        var user = FreeUser();
        var (sut, _) = ArrangeUpsell(reviewOptions, Smtp(), [user], alreadyEmailed: [user.UserId]);

        var result = await sut.RunUpsellAsync(2026, 8, dryRun: false);

        Assert.Equal(1, result.Data!.Skipped);
        analyticsProvider.Verify(
            a => a.GetPeriodSnapshotAsync(It.IsAny<Guid>(), It.IsAny<DateTime>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()),
            Times.Never);
        monthlyReviewProvider.Verify(
            p => p.RecordDeliveryAsync(It.IsAny<MonthlyReviewDeliveryModel>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task RunUpsellAsync_SendUpsellEmailsFalse_BuildsTeaserWithoutSendingEmail()
    {
        var reviewOptions = new MonthlyReviewOptions { SendUpsellEmails = false };
        var user = FreeUser();
        var (sut, _) = ArrangeUpsell(reviewOptions, Smtp(), [user]);
        analyticsProvider
            .Setup(a => a.GetPeriodSnapshotAsync(user.UserId, It.IsAny<DateTime>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(Snapshot());
        monthlyReviewProvider
            .Setup(p => p.RecordDeliveryAsync(
                It.Is<MonthlyReviewDeliveryModel>(d => d.Status == "Generated" && d.DeliveryKind == MonthlyReviewDeliveryKinds.Upsell),
                It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RunUpsellAsync(2026, 8, dryRun: false);

        Assert.False(result.Data!.EmailsEnabled);
        Assert.Equal(1, result.Data.ReportsGenerated);
        Assert.Equal(0, result.Data.EmailsSent);
        emailSender.Verify(e => e.SendAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task RunUpsellAsync_DryRun_DoesNotSendEmail()
    {
        var reviewOptions = ReviewOptions();
        var user = FreeUser();
        var (sut, _) = ArrangeUpsell(reviewOptions, Smtp(), [user]);
        analyticsProvider
            .Setup(a => a.GetPeriodSnapshotAsync(user.UserId, It.IsAny<DateTime>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(Snapshot());
        monthlyReviewProvider
            .Setup(p => p.RecordDeliveryAsync(It.IsAny<MonthlyReviewDeliveryModel>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RunUpsellAsync(2026, 8, dryRun: true);

        Assert.False(result.Data!.EmailsEnabled);
        Assert.Equal(0, result.Data.EmailsSent);
    }

    [Fact]
    public async Task RunUpsellAsync_NoEmailOnFile_IsSkippedWithoutSnapshotLookup()
    {
        var reviewOptions = ReviewOptions();
        var user = FreeUser(email: null);
        var (sut, _) = ArrangeUpsell(reviewOptions, Smtp(), [user]);

        var result = await sut.RunUpsellAsync(2026, 8, dryRun: false);

        Assert.Equal(1, result.Data!.Skipped);
        analyticsProvider.Verify(
            a => a.GetPeriodSnapshotAsync(It.IsAny<Guid>(), It.IsAny<DateTime>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()),
            Times.Never);
    }

    [Fact]
    public async Task RunUpsellAsync_SnapshotLookupThrows_CountsAsFailure()
    {
        var reviewOptions = ReviewOptions();
        var user = FreeUser();
        var (sut, _) = ArrangeUpsell(reviewOptions, Smtp(), [user]);
        analyticsProvider
            .Setup(a => a.GetPeriodSnapshotAsync(user.UserId, It.IsAny<DateTime>(), It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("snapshot down"));
        monthlyReviewProvider
            .Setup(p => p.RecordDeliveryAsync(
                It.Is<MonthlyReviewDeliveryModel>(d => d.Status == "Failed" && d.DeliveryKind == MonthlyReviewDeliveryKinds.Upsell),
                It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await sut.RunUpsellAsync(2026, 8, dryRun: false);

        Assert.Equal(1, result.Data!.Failures);
        Assert.Single(result.Data.FailureDetails);
    }
}
