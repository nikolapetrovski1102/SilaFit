using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="INotificationPublishService"/>
/// <remarks>
/// The batch is driven entirely by each user's stored timezone: it fetches the
/// raw UTC facts once, then converts to local time per user in memory. That is
/// deliberate - the server's own clock and zone never influence when someone is
/// reminded. Message copy lives in <see cref="NotificationMessageComposer"/>.
/// </remarks>
public sealed class NotificationPublishService(
    INotificationProvider notificationProvider,
    IPushNotificationSender pushSender,
    IOptions<NotificationPublishOptions> options,
    ILogger<NotificationPublishService> logger) : INotificationPublishService
{
    private const int MaxErrorLength = 1000;

    private enum DeliveryOutcome
    {
        Sent,
        Failed,
        Skipped
    }

    private sealed record PendingNotification(
        string Category,
        NotificationContent Content,
        string DedupeKey,
        DateTime ScheduledLocalAt);

    public Task<ServiceResult<NotificationPublishSummaryDto>> RunAsync(
        bool dryRun = false,
        Guid? onlyUserId = null,
        int? limit = null,
        CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var opts = options.Value;
            var startedAtUtc = DateTime.UtcNow;
            var summary = new NotificationPublishSummaryDto
            {
                DryRun = dryRun,
                PushConfigured = pushSender.IsConfigured,
                StartedAtUtc = startedAtUtc
            };

            if (!opts.Enabled)
            {
                logger.LogInformation("Notification publish is disabled (NotificationPublish:Enabled=false).");
                summary.CompletedAtUtc = DateTime.UtcNow;
                return summary;
            }

            // The cap is pushed into the query: without it this call materialized
            // every opted-in user and only then trimmed to MaxUsersPerRun in memory.
            var candidates = await notificationProvider.GetCandidatesAsync(opts.MaxUsersPerRun, cancellationToken).ConfigureAwait(false);
            if (onlyUserId is not null)
            {
                candidates = candidates.Where(c => c.UserId == onlyUserId).ToList();
            }

            if (limit is > 0)
            {
                candidates = candidates.Take(limit.Value).ToList();
            }

            if (candidates.Count > opts.MaxUsersPerRun)
            {
                candidates = candidates.Take(opts.MaxUsersPerRun).ToList();
            }

            summary.CandidatesConsidered = candidates.Count;
            var nowUtc = DateTime.UtcNow;

            foreach (var candidate in candidates)
            {
                try
                {
                    await ProcessCandidateAsync(candidate, nowUtc, dryRun, summary, cancellationToken).ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    summary.Failed++;
                    summary.Failures.Add(new NotificationPublishFailureDto
                    {
                        UserId = candidate.UserId,
                        Category = "Publish",
                        Message = ex.Message
                    });
                    logger.LogError(ex, "Notification publish failed for user {UserId}.", candidate.UserId);
                }
            }

            summary.CompletedAtUtc = DateTime.UtcNow;
            return summary;
        });

    public Task<ServiceResult<NotificationPublishSummaryDto>> FlushPendingAsync(
        bool dryRun = false,
        Guid? onlyUserId = null,
        CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var opts = options.Value;
            var summary = new NotificationPublishSummaryDto
            {
                DryRun = dryRun,
                PushConfigured = pushSender.IsConfigured,
                StartedAtUtc = DateTime.UtcNow
            };

            if (!opts.Enabled || !opts.PendingFlushEnabled)
            {
                summary.CompletedAtUtc = DateTime.UtcNow;
                return summary;
            }

            // Anything younger than the grace cutoff may belong to a run that is
            // still mid-flight (create -> deliver is milliseconds), so leave it.
            var cutoff = DateTime.UtcNow.AddMinutes(-Math.Max(1, opts.PendingFlushGraceMinutes));
            var pending = await notificationProvider
                .GetPendingNotificationsAsync(cutoff, Math.Max(1, opts.PendingFlushBatchSize), cancellationToken)
                .ConfigureAwait(false);

            if (onlyUserId is not null)
            {
                pending = pending.Where(n => n.UserId == onlyUserId).ToList();
            }

            summary.PendingConsidered = pending.Count;

            foreach (var notification in pending)
            {
                try
                {
                    if (dryRun)
                    {
                        logger.LogInformation(
                            "[dry-run] pending {Category} {NotificationId} -> {UserId} ({CreatedAtUtc:u}).",
                            notification.Category, notification.NotificationId, notification.UserId, notification.CreatedAtUtc);
                        continue;
                    }

                    var outcome = await DeliverAsync(notification.UserId, notification, cancellationToken).ConfigureAwait(false);
                    switch (outcome)
                    {
                        case DeliveryOutcome.Sent:
                            summary.PendingSent++;
                            break;
                        case DeliveryOutcome.Failed:
                            summary.PendingFailed++;
                            summary.Failures.Add(new NotificationPublishFailureDto
                            {
                                UserId = notification.UserId,
                                Category = notification.Category,
                                Message = "Pending push delivery failed."
                            });
                            break;
                        default:
                            summary.PendingSkipped++;
                            break;
                    }
                }
                catch (Exception ex)
                {
                    summary.PendingFailed++;
                    summary.Failures.Add(new NotificationPublishFailureDto
                    {
                        UserId = notification.UserId,
                        Category = notification.Category,
                        Message = Truncate(ex.Message, MaxErrorLength)
                    });
                    logger.LogError(ex, "Pending notification {NotificationId} flush failed.", notification.NotificationId);
                }
            }

            summary.CompletedAtUtc = DateTime.UtcNow;
            return summary;
        });

    private async Task ProcessCandidateAsync(
        NotificationCandidateModel candidate,
        DateTime nowUtc,
        bool dryRun,
        NotificationPublishSummaryDto summary,
        CancellationToken cancellationToken)
    {
        var pending = Decide(candidate, nowUtc, options.Value);
        if (pending is null)
        {
            summary.Suppressed++;
            return;
        }

        summary.WouldSend++;

        if (dryRun)
        {
            logger.LogInformation(
                "[dry-run] {Category} -> {UserId} ({Name}): {Title} | {Body}",
                pending.Category, candidate.UserId, candidate.DisplayName, pending.Content.Title, pending.Content.Body);
            return;
        }

        var created = await notificationProvider.TryCreateNotificationAsync(
            new NewNotificationModel
            {
                UserId = candidate.UserId,
                Category = pending.Category,
                Title = pending.Content.Title,
                Body = pending.Content.Body,
                DeepLink = pending.Content.Screen,
                DedupeKey = pending.DedupeKey,
                ScheduledLocalAt = pending.ScheduledLocalAt
            },
            cancellationToken).ConfigureAwait(false);

        if (created is null)
        {
            // Another run already enqueued this exact reminder in the last few minutes.
            summary.Suppressed++;
            return;
        }

        summary.Created++;

        var outcome = await DeliverAsync(candidate.UserId, created, cancellationToken).ConfigureAwait(false);
        switch (outcome)
        {
            case DeliveryOutcome.Sent:
                summary.Sent++;
                break;
            case DeliveryOutcome.Failed:
                summary.Failed++;
                summary.Failures.Add(new NotificationPublishFailureDto
                {
                    UserId = candidate.UserId,
                    Category = created.Category,
                    Message = "Push delivery failed."
                });
                break;
            default:
                summary.Skipped++;
                break;
        }
    }

    /// <summary>
    /// The whole scheduling policy, in one place and in the user's local time.
    /// Returns null when nothing should be sent right now.
    /// </summary>
    private static PendingNotification? Decide(
        NotificationCandidateModel candidate,
        DateTime nowUtc,
        NotificationPublishOptions opts)
    {
        if (candidate.ActiveTokenCount <= 0 || !candidate.NotificationsEnabled)
        {
            return null;
        }

        var timeZone = UserTimeZoneResolver.Resolve(candidate.TimeZoneId);
        var localNow = UserTimeZoneResolver.ToLocal(nowUtc, timeZone);
        var localDate = DateOnly.FromDateTime(localNow);

        // A rough day is capped regardless of category, so a bug can't turn into a spam storm.
        if (candidate.SentLast24h >= opts.MaxNotificationsPerDay)
        {
            return null;
        }

        // Nothing fires at night - including the comeback message, which waits
        // for the next morning rather than pinging at 03:00.
        if (localNow.Hour < opts.QuietHoursStart || localNow.Hour >= opts.QuietHoursEnd)
        {
            return null;
        }

        // 0. Monthly review upsell - once per local calendar month for users with
        //    no paid entitlement. Deliberately ahead of the silence backoff: it is
        //    a re-engagement/upgrade nudge rather than a training reminder, so a
        //    user who has gone quiet is exactly who it should reach. The
        //    "monthlyreview:{yyyy-MM}" dedupe key is what keeps it from ever
        //    repeating within the same local month, across every 5-minute tick.
        if (TryMonthlyReviewUpsell(candidate, localNow, localDate, opts, out var upsell))
        {
            return upsell;
        }

        var silence = nowUtc - (candidate.LastInteractionAtUtc ?? nowUtc);

        // Went quiet -> one comeback message, no matter what else would fire.
        if (silence >= TimeSpan.FromHours(opts.ComebackSilenceHours))
        {
            if (candidate.LastComebackAtUtc is DateTime lastComeback
                && nowUtc - lastComeback < TimeSpan.FromDays(opts.ComebackCooldownDays))
            {
                return null;
            }

            return new PendingNotification(
                NotificationCategories.Comeback,
                NotificationMessageComposer.Comeback(candidate),
                $"comeback:{localDate:yyyy-MM-dd}",
                localNow);
        }

        // Between "quiet down" and "comeback": stay silent.
        if (silence >= TimeSpan.FromHours(opts.InteractionSilenceHours))
        {
            return null;
        }

        // 1. Mid-workout set nudge - the most time-sensitive of the lot.
        if (TryTrackSets(candidate, nowUtc, localNow, localDate, opts, out var sets))
        {
            return sets;
        }

        // 2. The user's chosen training time, on a day they haven't trained yet.
        var preferredLocal = localNow.Date + candidate.NotificationLocalTime;
        if (IsInWindow(localNow, preferredLocal, opts.SendWindowMinutes)
            && !TrainedToday(candidate, timeZone, localDate))
        {
            return new PendingNotification(
                NotificationCategories.GymReminder,
                NotificationMessageComposer.GymReminder(candidate),
                $"gym:{localDate:yyyy-MM-dd}",
                preferredLocal);
        }

        // 3. Calorie / meal reminder around the configured local meal times.
        if (TryMealReminder(candidate, nowUtc, localNow, localDate, opts, out var meal))
        {
            return meal;
        }

        // 4. Gentle brag when they've been consistent this week.
        if (candidate.WorkoutsLast7Days >= 3
            && candidate.LastWorkoutCompletedAtUtc is DateTime lastCompleted
            && nowUtc - lastCompleted <= TimeSpan.FromHours(48)
            && (candidate.LastMotivationAtUtc is not DateTime lastMotivation
                || nowUtc - lastMotivation >= TimeSpan.FromDays(opts.MotivationMinGapDays)))
        {
            return new PendingNotification(
                NotificationCategories.Motivation,
                NotificationMessageComposer.Motivation(candidate),
                $"motivation:{localDate:yyyy-MM-dd}",
                localNow);
        }

        return null;
    }

    private static bool TryMonthlyReviewUpsell(
        NotificationCandidateModel candidate,
        DateTime localNow,
        DateOnly localDate,
        NotificationPublishOptions opts,
        out PendingNotification pending)
    {
        pending = null!;

        if (!opts.MonthlyReviewUpsellEnabled || candidate.HasPaidSubscription)
        {
            return false;
        }

        // Clamped to 1-28 so the configured day exists in every month.
        var day = Math.Clamp(opts.MonthlyReviewUpsellDayOfMonth, 1, 28);
        if (localDate.Day != day)
        {
            return false;
        }

        if (!TimeSpan.TryParse(opts.MonthlyReviewUpsellLocalTime, out var localTime))
        {
            return false;
        }

        var target = localNow.Date + localTime;
        if (!IsInWindow(localNow, target, opts.SendWindowMinutes))
        {
            return false;
        }

        pending = new PendingNotification(
            NotificationCategories.MonthlyReviewUpsell,
            NotificationMessageComposer.MonthlyReviewUpsell(candidate),
            $"monthlyreview:{localDate:yyyy-MM}",
            target);
        return true;
    }

    private static bool TryTrackSets(
        NotificationCandidateModel candidate,
        DateTime nowUtc,
        DateTime localNow,
        DateOnly localDate,
        NotificationPublishOptions opts,
        out PendingNotification pending)
    {
        pending = null!;

        if (candidate.ActiveSessionStartedAtUtc is not DateTime started
            || candidate.ActiveSessionLastActivityAtUtc is not DateTime activity)
        {
            return false;
        }

        var sessionAge = nowUtc - started;
        var idle = nowUtc - activity;
        var maxAge = TimeSpan.FromHours(opts.ActiveSessionMaxHours);

        if (sessionAge < TimeSpan.Zero || sessionAge > maxAge)
        {
            return false;
        }

        if (idle < TimeSpan.FromMinutes(opts.SetNudgeAfterMinutes) || idle > maxAge)
        {
            return false;
        }

        var cooldownMinutes = Math.Max(5, opts.SetNudgeCooldownMinutes);
        var bucket = (long)(nowUtc - DateTime.UnixEpoch).TotalMinutes / cooldownMinutes;

        pending = new PendingNotification(
            NotificationCategories.TrackSets,
            NotificationMessageComposer.TrackSets(candidate, idle),
            $"sets:{localDate:yyyy-MM-dd}:{bucket}",
            localNow);
        return true;
    }

    private static bool TryMealReminder(
        NotificationCandidateModel candidate,
        DateTime nowUtc,
        DateTime localNow,
        DateOnly localDate,
        NotificationPublishOptions opts,
        out PendingNotification pending)
    {
        pending = null!;
        var slots = opts.MealReminderLocalTimes ?? [];

        for (var i = 0; i < slots.Length; i++)
        {
            if (!TimeSpan.TryParse(slots[i], out var slotTime))
            {
                continue;
            }

            var slotAt = localNow.Date + slotTime;
            if (!IsInWindow(localNow, slotAt, opts.SendWindowMinutes))
            {
                continue;
            }

            if (candidate.LastMealLoggedAtUtc is DateTime lastMeal
                && nowUtc - lastMeal < TimeSpan.FromHours(opts.MealReminderMinGapHours))
            {
                continue;
            }

            var slotName = i switch { 0 => "lunch", 1 => "dinner", _ => $"meal{i}" };

            // Alternate "log what you ate" with "here's an idea" per slot so the
            // two meal messages don't feel like the same nag twice a day.
            var useIdea = i % 2 == 1;
            var category = useIdea ? NotificationCategories.MealIdea : NotificationCategories.TrackCalories;
            var content = useIdea
                ? NotificationMessageComposer.MealIdea(candidate)
                : NotificationMessageComposer.TrackCalories(candidate);

            pending = new PendingNotification(
                category,
                content,
                $"{category.ToLowerInvariant()}:{localDate:yyyy-MM-dd}:{slotName}",
                slotAt);
            return true;
        }

        return false;
    }

    private static bool IsInWindow(DateTime localNow, DateTime targetLocal, int windowMinutes)
    {
        var delta = localNow - targetLocal;
        return delta >= TimeSpan.Zero && delta <= TimeSpan.FromMinutes(Math.Max(1, windowMinutes));
    }

    private static bool TrainedToday(NotificationCandidateModel candidate, TimeZoneInfo timeZone, DateOnly localDate)
    {
        if (candidate.LastWorkoutStartedAtUtc is DateTime started
            && DateOnly.FromDateTime(UserTimeZoneResolver.ToLocal(started, timeZone)) == localDate)
        {
            return true;
        }

        return candidate.LastWorkoutCompletedAtUtc is DateTime completed
               && DateOnly.FromDateTime(UserTimeZoneResolver.ToLocal(completed, timeZone)) == localDate;
    }

    private async Task<DeliveryOutcome> DeliverAsync(
        Guid userId,
        UserNotificationModel notification,
        CancellationToken cancellationToken)
    {
        var tokens = await notificationProvider
            .GetActiveDeviceTokensAsync(userId, cancellationToken)
            .ConfigureAwait(false);

        if (tokens.Count == 0)
        {
            await notificationProvider
                .MarkSkippedAsync(notification.NotificationId, "No active device tokens.", cancellationToken)
                .ConfigureAwait(false);
            return DeliveryOutcome.Skipped;
        }

        var delivered = false;
        string? providerMessageId = null;
        var errors = new List<string>();

        foreach (var token in tokens)
        {
            var message = new PushNotificationMessage
            {
                Token = token.PushToken,
                Title = notification.Title,
                Body = notification.Body,
                Data = new Dictionary<string, string>
                {
                    ["notificationId"] = notification.NotificationId.ToString(),
                    ["category"] = notification.Category,
                    ["screen"] = notification.DeepLink ?? "today"
                }
            };

            PushSendResult result;
            try
            {
                result = await pushSender.SendAsync(message, cancellationToken).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                result = PushSendResult.Failed(ex.Message);
            }

            if (result.Success)
            {
                delivered = true;
                providerMessageId ??= result.ProviderMessageId;
                continue;
            }

            errors.Add($"{token.Platform}: {result.Error}");

            if (result.TokenInvalid)
            {
                await notificationProvider
                    .DeactivateDeviceTokenAsync(userId, token.PushToken, cancellationToken)
                    .ConfigureAwait(false);
            }
        }

        if (delivered)
        {
            await notificationProvider
                .MarkSentAsync(notification.NotificationId, notification.Category, providerMessageId, DateTime.UtcNow, cancellationToken)
                .ConfigureAwait(false);
            return DeliveryOutcome.Sent;
        }

        var error = errors.Count > 0 ? string.Join("; ", errors) : "Push delivery failed.";
        await notificationProvider
            .MarkFailedAsync(notification.NotificationId, Truncate(error, MaxErrorLength), cancellationToken)
            .ConfigureAwait(false);
        return DeliveryOutcome.Failed;
    }

    private static string Truncate(string value, int maxLength) =>
        value.Length <= maxLength ? value : value[..maxLength];
}
