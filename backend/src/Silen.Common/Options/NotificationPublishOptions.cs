namespace Silen.Common.Options;

/// <summary>
/// Tunables for the notification publish service. Every time-based value is
/// expressed in the *user's* local timezone at decision time - the scheduler
/// converts UTC to each candidate's zone before applying them.
/// </summary>
public sealed class NotificationPublishOptions
{
    public const string SectionName = "NotificationPublish";

    /// <summary>Master switch. When false the batch does nothing at all.</summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// When true, the API hosts the publisher as a background service too (in
    /// addition to / instead of the cron tool). Off by default so the two can
    /// never double-run in a deployment that uses the cron entry; the dedupe
    /// keys make an overlap harmless, just wasteful.
    /// </summary>
    public bool RunInApi { get; set; }

    /// <summary>How often the in-API background service ticks. Ignored by the cron tool.</summary>
    public int PollMinutes { get; set; } = 5;

    /// <summary>
    /// Width of the window after a configured local time during which a
    /// reminder may fire. Keeps a "18:00" preference working even if the batch
    /// ticks a few minutes late.
    /// </summary>
    public int SendWindowMinutes { get; set; } = 45;

    /// <summary>Local times (HH:mm) at which calorie/meal reminders may fire.</summary>
    public string[] MealReminderLocalTimes { get; set; } = ["12:30", "18:30"];

    /// <summary>Don't repeat a calorie/meal nudge if the user logged food more recently than this.</summary>
    public int MealReminderMinGapHours { get; set; } = 4;

    /// <summary>Minutes of in-workout idleness before the "log your sets" nudge.</summary>
    public int SetNudgeAfterMinutes { get; set; } = 20;

    /// <summary>Minimum gap between two "log your sets" nudges in one session.</summary>
    public int SetNudgeCooldownMinutes { get; set; } = 30;

    /// <summary>A heartbeat older than this no longer counts as "currently in the gym".</summary>
    public int ActiveSessionMaxHours { get; set; } = 6;

    /// <summary>After this much silence, normal reminders stop (the app is clearly not being used).</summary>
    public int InteractionSilenceHours { get; set; } = 30;

    /// <summary>After this much silence, send the single comeback message instead.</summary>
    public int ComebackSilenceHours { get; set; } = 48;

    /// <summary>Minimum gap between two comeback messages.</summary>
    public int ComebackCooldownDays { get; set; } = 3;

    /// <summary>Minimum gap between two motivational messages.</summary>
    public int MotivationMinGapDays { get; set; } = 3;

    /// <summary>Hard daily cap per user across every category, so a bad day can't spam.</summary>
    public int MaxNotificationsPerDay { get; set; } = 6;

    /// <summary>Safety cap on candidates processed in a single run.</summary>
    public int MaxUsersPerRun { get; set; } = 5000;

    /// <summary>
    /// Safety net for the outbox: each run also re-delivers notifications a
    /// previous run left in 'Created' (crash or hard transport failure), so a
    /// reminder can never be silently stranded. On by default; with a live
    /// transport this only ever touches genuinely orphaned rows.
    /// </summary>
    public bool PendingFlushEnabled { get; set; } = true;

    /// <summary>
    /// Only flush 'Created' rows older than this. The create -> deliver window
    /// is milliseconds, so the margin exists purely to avoid racing a run that
    /// is currently mid-flight.
    /// </summary>
    public int PendingFlushGraceMinutes { get; set; } = 30;

    /// <summary>Safety cap on stranded notifications retried in a single run.</summary>
    public int PendingFlushBatchSize { get; set; } = 200;

    /// <summary>No notifications outside this local-hour range (24h clock, end-exclusive).</summary>
    public int QuietHoursStart { get; set; } = 7;

    public int QuietHoursEnd { get; set; } = 22;

    /// <summary>
    /// Master switch for the monthly-review upsell push (non-paying users only).
    /// On by default; the dedupe key makes it once per local calendar month even
    /// though the batch ticks every few minutes.
    /// </summary>
    public bool MonthlyReviewUpsellEnabled { get; set; } = true;

    /// <summary>
    /// Local day of month the upsell push may fire on (clamped to 1-28 so every
    /// month has the day). Defaults to the 1st, matching the monthly email batch.
    /// </summary>
    public int MonthlyReviewUpsellDayOfMonth { get; set; } = 1;

    /// <summary>
    /// Local time (HH:mm) the upsell push targets on that day; the usual
    /// <see cref="SendWindowMinutes"/> window applies.
    /// </summary>
    public string MonthlyReviewUpsellLocalTime { get; set; } = "09:00";
}
