using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Moq;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class NotificationPublishServiceTests
{
    private readonly Mock<INotificationProvider> notificationProvider = new(MockBehavior.Strict);
    private readonly Mock<IPushNotificationSender> pushSender = new(MockBehavior.Strict);

    private NotificationPublishService Sut(NotificationPublishOptions options) =>
        new(notificationProvider.Object, pushSender.Object, Options.Create(options), NullLogger<NotificationPublishService>.Instance);

    private static NotificationPublishOptions BuildOptions(Action<NotificationPublishOptions>? configure = null)
    {
        var options = new NotificationPublishOptions
        {
            Enabled = true,
            QuietHoursStart = 0,
            QuietHoursEnd = 24,
            SendWindowMinutes = 45,
            MaxNotificationsPerDay = 6,
            MaxUsersPerRun = 5000,
            InteractionSilenceHours = 30,
            ComebackSilenceHours = 48,
            ComebackCooldownDays = 3,
            MotivationMinGapDays = 3,
            MealReminderMinGapHours = 4,
            SetNudgeAfterMinutes = 20,
            SetNudgeCooldownMinutes = 30,
            ActiveSessionMaxHours = 6,
            // Off unless a test opts in: the monthly upsell is day/time gated, so
            // leaving it on would make the wall-clock-based tests flaky.
            MonthlyReviewUpsellEnabled = false
        };
        configure?.Invoke(options);
        return options;
    }

    private static NotificationCandidateModel Candidate(
        Guid? userId = null,
        bool notificationsEnabled = true,
        int activeTokenCount = 1,
        DateTime? lastInteractionAtUtc = null,
        int sentLast24h = 0,
        DateTime? lastComebackAtUtc = null,
        bool hasPaidSubscription = false) => new()
    {
        UserId = userId ?? Guid.NewGuid(),
        DisplayName = "Test User",
        NotificationsEnabled = notificationsEnabled,
        NotificationLocalTime = TimeSpan.FromHours(8),
        TimeZoneId = "UTC",
        LastInteractionAtUtc = lastInteractionAtUtc,
        SentLast24h = sentLast24h,
        LastComebackAtUtc = lastComebackAtUtc,
        HasPaidSubscription = hasPaidSubscription,
        ActiveTokenCount = activeTokenCount
    };

    [Fact]
    public async Task RunAsync_PublishDisabled_ReturnsSummaryWithoutQueryingCandidates()
    {
        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        var options = BuildOptions(o => o.Enabled = false);

        var result = await Sut(options).RunAsync();

        Assert.True(result.IsSuccess);
        Assert.Equal(0, result.Data!.CandidatesConsidered);
        Assert.True(result.Data.PushConfigured);
    }

    [Fact]
    public async Task RunAsync_CandidateWithNoActiveTokens_IsSuppressed()
    {
        var options = BuildOptions();
        var candidate = Candidate(activeTokenCount: 0);
        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);

        var result = await Sut(options).RunAsync();

        Assert.True(result.IsSuccess);
        Assert.Equal(1, result.Data!.Suppressed);
        Assert.Equal(0, result.Data.Created);
    }

    [Fact]
    public async Task RunAsync_CandidateWithNotificationsDisabled_IsSuppressed()
    {
        var options = BuildOptions();
        var candidate = Candidate(notificationsEnabled: false);
        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);

        var result = await Sut(options).RunAsync();

        Assert.Equal(1, result.Data!.Suppressed);
        Assert.Equal(0, result.Data.Created);
    }

    [Fact]
    public async Task RunAsync_DailyCapReached_IsSuppressed()
    {
        var options = BuildOptions(o => o.MaxNotificationsPerDay = 6);
        var candidate = Candidate(sentLast24h: 10);
        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);

        var result = await Sut(options).RunAsync();

        Assert.Equal(1, result.Data!.Suppressed);
        Assert.Equal(0, result.Data.Created);
    }

    [Fact]
    public async Task RunAsync_OutsideQuietHours_IsSuppressed()
    {
        // QuietHoursStart above every possible local hour (0-23) guarantees the
        // "outside quiet hours" branch fires deterministically, regardless of wall-clock time.
        var options = BuildOptions(o => o.QuietHoursStart = 100);
        var candidate = Candidate();
        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);

        var result = await Sut(options).RunAsync();

        Assert.Equal(1, result.Data!.Suppressed);
        Assert.Equal(0, result.Data.Created);
    }

    [Fact]
    public async Task RunAsync_SilenceBetweenInteractionAndComebackThresholds_IsSuppressed()
    {
        var options = BuildOptions(o =>
        {
            o.InteractionSilenceHours = 30;
            o.ComebackSilenceHours = 48;
        });
        var candidate = Candidate(lastInteractionAtUtc: DateTime.UtcNow.AddHours(-35));
        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);

        var result = await Sut(options).RunAsync();

        Assert.Equal(1, result.Data!.Suppressed);
        Assert.Equal(0, result.Data.Created);
    }

    [Fact]
    public async Task RunAsync_ComebackWithinCooldown_IsSuppressed()
    {
        var options = BuildOptions();
        var candidate = Candidate(lastInteractionAtUtc: DateTime.UtcNow.AddHours(-100), lastComebackAtUtc: DateTime.UtcNow.AddDays(-1));
        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);

        var result = await Sut(options).RunAsync();

        Assert.Equal(1, result.Data!.Suppressed);
        Assert.Equal(0, result.Data.Created);
    }

    [Fact]
    public async Task RunAsync_LongSilence_CreatesAndSendsComebackNotification()
    {
        var options = BuildOptions();
        var candidate = Candidate(lastInteractionAtUtc: DateTime.UtcNow.AddHours(-100));
        var notification = new UserNotificationModel
        {
            NotificationId = Guid.NewGuid(),
            UserId = candidate.UserId,
            Category = NotificationCategories.Comeback
        };

        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);
        notificationProvider
            .Setup(p => p.TryCreateNotificationAsync(
                It.Is<NewNotificationModel>(n => n.Category == NotificationCategories.Comeback && n.UserId == candidate.UserId),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(notification);
        notificationProvider
            .Setup(p => p.GetActiveDeviceTokensAsync(candidate.UserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([new UserDeviceTokenModel { PushToken = "tok1", Platform = "ios" }]);
        pushSender
            .Setup(p => p.SendAsync(It.IsAny<PushNotificationMessage>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(PushSendResult.Sent("provider-msg"));
        notificationProvider
            .Setup(p => p.MarkSentAsync(notification.NotificationId, notification.Category, "provider-msg", It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await Sut(options).RunAsync();

        Assert.True(result.IsSuccess);
        Assert.Equal(1, result.Data!.Created);
        Assert.Equal(1, result.Data.Sent);
        Assert.Equal(0, result.Data.Failed);
    }

    [Fact]
    public async Task RunAsync_DryRun_CountsWouldSendButCreatesNothing()
    {
        var options = BuildOptions();
        var candidate = Candidate(lastInteractionAtUtc: DateTime.UtcNow.AddHours(-100));
        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);

        var result = await Sut(options).RunAsync(dryRun: true);

        Assert.True(result.IsSuccess);
        Assert.Equal(1, result.Data!.WouldSend);
        Assert.Equal(0, result.Data.Created);
    }

    [Fact]
    public async Task RunAsync_DuplicateDedupeKey_IsSuppressed()
    {
        var options = BuildOptions();
        var candidate = Candidate(lastInteractionAtUtc: DateTime.UtcNow.AddHours(-100));
        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);
        notificationProvider
            .Setup(p => p.TryCreateNotificationAsync(It.IsAny<NewNotificationModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((UserNotificationModel?)null);

        var result = await Sut(options).RunAsync();

        Assert.Equal(1, result.Data!.Suppressed);
        Assert.Equal(0, result.Data.Created);
    }

    [Fact]
    public async Task RunAsync_NoActiveTokensAtDeliveryTime_MarksNotificationSkipped()
    {
        var options = BuildOptions();
        var candidate = Candidate(lastInteractionAtUtc: DateTime.UtcNow.AddHours(-100));
        var notification = new UserNotificationModel
        {
            NotificationId = Guid.NewGuid(),
            UserId = candidate.UserId,
            Category = NotificationCategories.Comeback
        };

        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);
        notificationProvider
            .Setup(p => p.TryCreateNotificationAsync(It.IsAny<NewNotificationModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(notification);
        notificationProvider
            .Setup(p => p.GetActiveDeviceTokensAsync(candidate.UserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([]);
        notificationProvider
            .Setup(p => p.MarkSkippedAsync(notification.NotificationId, It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await Sut(options).RunAsync();

        Assert.Equal(1, result.Data!.Created);
        Assert.Equal(1, result.Data.Skipped);
        Assert.Equal(0, result.Data.Sent);
    }

    [Fact]
    public async Task RunAsync_PushFailsWithInvalidToken_MarksFailedAndDeactivatesToken()
    {
        var options = BuildOptions();
        var candidate = Candidate(lastInteractionAtUtc: DateTime.UtcNow.AddHours(-100));
        var notification = new UserNotificationModel
        {
            NotificationId = Guid.NewGuid(),
            UserId = candidate.UserId,
            Category = NotificationCategories.Comeback
        };

        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);
        notificationProvider
            .Setup(p => p.TryCreateNotificationAsync(It.IsAny<NewNotificationModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(notification);
        notificationProvider
            .Setup(p => p.GetActiveDeviceTokensAsync(candidate.UserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([new UserDeviceTokenModel { PushToken = "bad-token", Platform = "ios" }]);
        pushSender
            .Setup(p => p.SendAsync(It.IsAny<PushNotificationMessage>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(PushSendResult.Failed("Unregistered", tokenInvalid: true));
        notificationProvider
            .Setup(p => p.DeactivateDeviceTokenAsync(candidate.UserId, "bad-token", It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        notificationProvider
            .Setup(p => p.MarkFailedAsync(notification.NotificationId, It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await Sut(options).RunAsync();

        Assert.Equal(1, result.Data!.Failed);
        Assert.Single(result.Data.Failures);
        notificationProvider.Verify(p => p.DeactivateDeviceTokenAsync(candidate.UserId, "bad-token", It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task RunAsync_OnlyUserIdFilter_ProcessesOnlyThatCandidate()
    {
        var options = BuildOptions();
        var target = Candidate(notificationsEnabled: false);
        var other = Candidate(notificationsEnabled: false);
        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([target, other]);

        var result = await Sut(options).RunAsync(onlyUserId: target.UserId);

        Assert.Equal(1, result.Data!.CandidatesConsidered);
    }

    [Fact]
    public async Task RunAsync_LimitParameter_TrimsCandidateList()
    {
        var options = BuildOptions();
        var candidates = new List<NotificationCandidateModel>
        {
            Candidate(notificationsEnabled: false),
            Candidate(notificationsEnabled: false),
            Candidate(notificationsEnabled: false)
        };
        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync(candidates);

        var result = await Sut(options).RunAsync(limit: 1);

        Assert.Equal(1, result.Data!.CandidatesConsidered);
    }

    [Fact]
    public async Task RunAsync_ProviderReturnsMoreThanMaxUsersPerRun_TrimsToCap()
    {
        var options = BuildOptions(o => o.MaxUsersPerRun = 1);
        var candidates = new List<NotificationCandidateModel>
        {
            Candidate(notificationsEnabled: false),
            Candidate(notificationsEnabled: false)
        };
        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(1, It.IsAny<CancellationToken>())).ReturnsAsync(candidates);

        var result = await Sut(options).RunAsync();

        Assert.Equal(1, result.Data!.CandidatesConsidered);
    }

    [Fact]
    public async Task RunAsync_ExceptionWhileProcessingCandidate_IsCaughtAndCountedAsFailure()
    {
        var options = BuildOptions();
        var candidate = Candidate(lastInteractionAtUtc: DateTime.UtcNow.AddHours(-100));
        var notification = new UserNotificationModel
        {
            NotificationId = Guid.NewGuid(),
            UserId = candidate.UserId,
            Category = NotificationCategories.Comeback
        };

        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);
        notificationProvider
            .Setup(p => p.TryCreateNotificationAsync(It.IsAny<NewNotificationModel>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(notification);
        notificationProvider
            .Setup(p => p.GetActiveDeviceTokensAsync(candidate.UserId, It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("db unavailable"));

        var result = await Sut(options).RunAsync();

        Assert.True(result.IsSuccess);
        Assert.Equal(1, result.Data!.Failed);
        Assert.Single(result.Data.Failures);
    }

    [Fact]
    public async Task RunAsync_UsesEachUsersPreferredLocalTimeAndTimeZone()
    {
        var options = BuildOptions(o => o.MealReminderLocalTimes = []);
        var utcNow = DateTime.UtcNow;
        var localNow = utcNow.AddHours(5).AddMinutes(45);
        var candidate = Candidate(lastInteractionAtUtc: utcNow);
        candidate.TimeZoneId = "+05:45";
        candidate.NotificationLocalTime = new TimeSpan(localNow.Hour, localNow.Minute, 0);

        var notification = new UserNotificationModel
        {
            NotificationId = Guid.NewGuid(),
            UserId = candidate.UserId,
            Category = NotificationCategories.GymReminder
        };
        NewNotificationModel? createdReminder = null;

        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider
            .Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>()))
            .ReturnsAsync([candidate]);
        notificationProvider
            .Setup(p => p.TryCreateNotificationAsync(It.IsAny<NewNotificationModel>(), It.IsAny<CancellationToken>()))
            .Callback<NewNotificationModel, CancellationToken>((created, _) => createdReminder = created)
            .ReturnsAsync(notification);
        notificationProvider
            .Setup(p => p.GetActiveDeviceTokensAsync(candidate.UserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([new UserDeviceTokenModel { PushToken = "tok1", Platform = "ios" }]);
        pushSender
            .Setup(p => p.SendAsync(It.IsAny<PushNotificationMessage>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(PushSendResult.Sent("provider-msg"));
        notificationProvider
            .Setup(p => p.MarkSentAsync(notification.NotificationId, notification.Category, "provider-msg", It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await Sut(options).RunAsync();

        Assert.True(result.IsSuccess);
        Assert.NotNull(createdReminder);
        Assert.Equal(NotificationCategories.GymReminder, createdReminder.Category);
        Assert.Equal(candidate.NotificationLocalTime, createdReminder.ScheduledLocalAt!.Value.TimeOfDay);
        Assert.Equal($"gym:{createdReminder.ScheduledLocalAt:yyyy-MM-dd}", createdReminder.DedupeKey);
    }

    [Fact]
    public async Task FlushPendingAsync_MasterSwitchDisabled_DoesNotQueryPending()
    {
        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        var options = BuildOptions(o => o.Enabled = false);

        var result = await Sut(options).FlushPendingAsync();

        Assert.True(result.IsSuccess);
        Assert.Equal(0, result.Data!.PendingConsidered);
    }

    [Fact]
    public async Task FlushPendingAsync_PendingFlushDisabled_DoesNotQueryPending()
    {
        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        var options = BuildOptions(o => o.PendingFlushEnabled = false);

        var result = await Sut(options).FlushPendingAsync();

        Assert.True(result.IsSuccess);
        Assert.Equal(0, result.Data!.PendingConsidered);
    }

    [Fact]
    public async Task FlushPendingAsync_DeliversPendingAndMarksSent()
    {
        var options = BuildOptions();
        var userId = Guid.NewGuid();
        var notification = new UserNotificationModel
        {
            NotificationId = Guid.NewGuid(),
            UserId = userId,
            Category = NotificationCategories.Motivation
        };

        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider
            .Setup(p => p.GetPendingNotificationsAsync(It.IsAny<DateTime>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync([notification]);
        notificationProvider
            .Setup(p => p.GetActiveDeviceTokensAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([new UserDeviceTokenModel { PushToken = "tok1", Platform = "ios" }]);
        pushSender
            .Setup(p => p.SendAsync(It.IsAny<PushNotificationMessage>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(PushSendResult.Sent("provider-msg"));
        notificationProvider
            .Setup(p => p.MarkSentAsync(notification.NotificationId, notification.Category, "provider-msg", It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await Sut(options).FlushPendingAsync();

        Assert.True(result.IsSuccess);
        Assert.Equal(1, result.Data!.PendingConsidered);
        Assert.Equal(1, result.Data.PendingSent);
        Assert.Equal(0, result.Data.PendingFailed);
    }

    [Fact]
    public async Task FlushPendingAsync_NoActiveTokens_MarksNotificationSkipped()
    {
        var options = BuildOptions();
        var userId = Guid.NewGuid();
        var notification = new UserNotificationModel
        {
            NotificationId = Guid.NewGuid(),
            UserId = userId,
            Category = NotificationCategories.GymReminder
        };

        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider
            .Setup(p => p.GetPendingNotificationsAsync(It.IsAny<DateTime>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync([notification]);
        notificationProvider
            .Setup(p => p.GetActiveDeviceTokensAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([]);
        notificationProvider
            .Setup(p => p.MarkSkippedAsync(notification.NotificationId, It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await Sut(options).FlushPendingAsync();

        Assert.Equal(1, result.Data!.PendingConsidered);
        Assert.Equal(1, result.Data.PendingSkipped);
        Assert.Equal(0, result.Data.PendingSent);
    }

    [Fact]
    public async Task FlushPendingAsync_DryRun_CountsButDoesNotDeliver()
    {
        var options = BuildOptions();
        var notification = new UserNotificationModel
        {
            NotificationId = Guid.NewGuid(),
            UserId = Guid.NewGuid(),
            Category = NotificationCategories.Comeback
        };

        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider
            .Setup(p => p.GetPendingNotificationsAsync(It.IsAny<DateTime>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync([notification]);

        var result = await Sut(options).FlushPendingAsync(dryRun: true);

        Assert.True(result.IsSuccess);
        Assert.Equal(1, result.Data!.PendingConsidered);
        Assert.Equal(0, result.Data.PendingSent);
        Assert.Equal(0, result.Data.PendingSkipped);
    }

    [Fact]
    public async Task FlushPendingAsync_OnlyUserIdFilter_ProcessesOnlyThatUser()
    {
        var options = BuildOptions();
        var target = new UserNotificationModel
        {
            NotificationId = Guid.NewGuid(),
            UserId = Guid.NewGuid(),
            Category = NotificationCategories.Comeback
        };
        var other = new UserNotificationModel
        {
            NotificationId = Guid.NewGuid(),
            UserId = Guid.NewGuid(),
            Category = NotificationCategories.Comeback
        };

        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider
            .Setup(p => p.GetPendingNotificationsAsync(It.IsAny<DateTime>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync([target, other]);
        notificationProvider
            .Setup(p => p.GetActiveDeviceTokensAsync(target.UserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([]);
        notificationProvider
            .Setup(p => p.MarkSkippedAsync(target.NotificationId, It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await Sut(options).FlushPendingAsync(onlyUserId: target.UserId);

        Assert.Equal(1, result.Data!.PendingConsidered);
        Assert.Equal(1, result.Data.PendingSkipped);
        notificationProvider.Verify(p => p.GetActiveDeviceTokensAsync(other.UserId, It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task FlushPendingAsync_TransportFailure_MarksFailedAndCounts()
    {
        var options = BuildOptions();
        var userId = Guid.NewGuid();
        var notification = new UserNotificationModel
        {
            NotificationId = Guid.NewGuid(),
            UserId = userId,
            Category = NotificationCategories.MealIdea
        };

        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider
            .Setup(p => p.GetPendingNotificationsAsync(It.IsAny<DateTime>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync([notification]);
        notificationProvider
            .Setup(p => p.GetActiveDeviceTokensAsync(userId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([new UserDeviceTokenModel { PushToken = "tok1", Platform = "android" }]);
        pushSender
            .Setup(p => p.SendAsync(It.IsAny<PushNotificationMessage>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(PushSendResult.Failed("boom"));
        notificationProvider
            .Setup(p => p.MarkFailedAsync(notification.NotificationId, It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await Sut(options).FlushPendingAsync();

        Assert.Equal(1, result.Data!.PendingConsidered);
        Assert.Equal(1, result.Data.PendingFailed);
        Assert.Single(result.Data.Failures);
    }

    // -------------------------------------------------------------------------
    // Monthly review upsell (non-paying users only)
    // -------------------------------------------------------------------------

    /// <summary>Options that put the upsell window around "right now" so the test is
    /// not tied to a particular wall-clock instant, with the other scheduling rules
    /// neutralised so only the upsell can fire.</summary>
    private static NotificationPublishOptions UpsellOptions(Action<NotificationPublishOptions>? configure = null)
    {
        var now = DateTime.UtcNow;
        return BuildOptions(o =>
        {
            o.MonthlyReviewUpsellEnabled = true;
            o.MonthlyReviewUpsellDayOfMonth = now.Day;
            o.MonthlyReviewUpsellLocalTime = $"{now.Hour:00}:{now.Minute:00}";
            o.SendWindowMinutes = 45;
            o.MealReminderLocalTimes = [];
            configure?.Invoke(o);
        });
    }

    private static NotificationCandidateModel UpsellCandidate(bool hasPaidSubscription)
    {
        var candidate = Candidate(hasPaidSubscription: hasPaidSubscription);
        // Half a day away from the upsell target, so the gym-reminder rule cannot fire.
        candidate.NotificationLocalTime = TimeSpan.FromHours((DateTime.UtcNow.Hour + 12) % 24);
        return candidate;
    }

    [Fact]
    public async Task RunAsync_NonPayingCandidateOnUpsellDay_CreatesMonthlyReviewUpsell()
    {
        var options = UpsellOptions();
        var candidate = UpsellCandidate(hasPaidSubscription: false);
        var notification = new UserNotificationModel
        {
            NotificationId = Guid.NewGuid(),
            UserId = candidate.UserId,
            Category = NotificationCategories.MonthlyReviewUpsell
        };

        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);
        notificationProvider
            .Setup(p => p.TryCreateNotificationAsync(
                It.Is<NewNotificationModel>(n =>
                    n.Category == NotificationCategories.MonthlyReviewUpsell
                    && n.UserId == candidate.UserId
                    && n.DedupeKey.StartsWith("monthlyreview:")),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(notification);
        notificationProvider
            .Setup(p => p.GetActiveDeviceTokensAsync(candidate.UserId, It.IsAny<CancellationToken>()))
            .ReturnsAsync([new UserDeviceTokenModel { PushToken = "tok1", Platform = "ios" }]);
        pushSender
            .Setup(p => p.SendAsync(It.IsAny<PushNotificationMessage>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(PushSendResult.Sent("provider-msg"));
        notificationProvider
            .Setup(p => p.MarkSentAsync(notification.NotificationId, notification.Category, "provider-msg", It.IsAny<DateTime>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var result = await Sut(options).RunAsync();

        Assert.Equal(1, result.Data!.Created);
        Assert.Equal(1, result.Data.Sent);
    }

    [Fact]
    public async Task RunAsync_PayingCandidateOnUpsellDay_IsNotSentUpsell()
    {
        var options = UpsellOptions();
        var candidate = UpsellCandidate(hasPaidSubscription: true);

        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);

        var result = await Sut(options).RunAsync();

        Assert.Equal(1, result.Data!.Suppressed);
        Assert.Equal(0, result.Data.Created);
        notificationProvider.Verify(
            p => p.TryCreateNotificationAsync(It.IsAny<NewNotificationModel>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task RunAsync_NonPayingCandidateOnWrongDay_IsNotSentUpsell()
    {
        var today = DateTime.UtcNow.Day;
        var options = UpsellOptions(o => o.MonthlyReviewUpsellDayOfMonth = today == 1 ? 2 : 1);
        var candidate = UpsellCandidate(hasPaidSubscription: false);

        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);

        var result = await Sut(options).RunAsync();

        Assert.Equal(1, result.Data!.Suppressed);
        Assert.Equal(0, result.Data.Created);
    }

    [Fact]
    public async Task RunAsync_UpsellDisabledForNonPayingCandidate_IsSuppressed()
    {
        var options = UpsellOptions(o => o.MonthlyReviewUpsellEnabled = false);
        var candidate = UpsellCandidate(hasPaidSubscription: false);

        pushSender.SetupGet(p => p.IsConfigured).Returns(true);
        notificationProvider.Setup(p => p.GetCandidatesAsync(options.MaxUsersPerRun, It.IsAny<CancellationToken>())).ReturnsAsync([candidate]);

        var result = await Sut(options).RunAsync();

        Assert.Equal(1, result.Data!.Suppressed);
        Assert.Equal(0, result.Data.Created);
    }
}
