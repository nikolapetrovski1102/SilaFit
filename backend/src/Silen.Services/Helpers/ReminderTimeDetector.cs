namespace Silen.Services.Helpers;

/// <summary>
/// Learns when a user habitually trains / eats from the times they actually log
/// workouts and meals, so reminders land on their routine instead of a fixed
/// clock. Pure and timezone-aware: callers hand in raw UTC history plus the
/// user's zone, and get back a local time-of-day (or null when the history is
/// too thin to trust, in which case the caller keeps its default).
/// </summary>
public static class ReminderTimeDetector
{
    /// <summary>How far back the history goes; the SQL that feeds this uses the same window.</summary>
    public const int LookbackDays = 28;

    /// <summary>Distinct days of evidence needed before a habit is trusted over the default.</summary>
    public const int MinDays = 3;

    /// <summary>How far a meal log may sit from a reminder slot and still count towards it.</summary>
    public static readonly TimeSpan MealSlotRadius = TimeSpan.FromHours(2);

    private const int RoundToMinutes = 5;

    /// <summary>
    /// The user's typical workout start: the median of each day's first start
    /// (one per day, so a double session doesn't count twice), rounded to 5 min.
    /// </summary>
    public static TimeSpan? DetectWorkoutTime(IEnumerable<DateTime> startsUtc, TimeZoneInfo timeZone, DateTime nowUtc)
    {
        var perDay = Localize(startsUtc, timeZone, nowUtc)
            .GroupBy(t => t.Date)
            .Select(g => g.Min().TimeOfDay)
            .ToList();

        return Median(perDay);
    }

    /// <summary>
    /// The user's typical log time for the meal around <paramref name="slot"/>:
    /// per day, the log closest to the slot within <see cref="MealSlotRadius"/>,
    /// then the median of those. Breakfast logs never drag the lunch slot, etc.
    /// </summary>
    public static TimeSpan? DetectMealTime(IEnumerable<DateTime> loggedUtc, TimeZoneInfo timeZone, DateTime nowUtc, TimeSpan slot)
    {
        var perDay = Localize(loggedUtc, timeZone, nowUtc)
            .Where(t => (t.TimeOfDay - slot).Duration() <= MealSlotRadius)
            .GroupBy(t => t.Date)
            .Select(g => g.MinBy(t => (t.TimeOfDay - slot).Duration()).TimeOfDay)
            .ToList();

        return Median(perDay);
    }

    /// <summary>
    /// When the gym reminder fires today. A time the user picked is used exactly;
    /// otherwise <paramref name="leadMinutes"/> ahead of their detected training
    /// time, falling back to the stored time (18:00 by default) with no history.
    /// </summary>
    public static TimeSpan GymReminderTime(
        TimeSpan storedLocalTime,
        bool isUserSet,
        IEnumerable<DateTime> workoutStartsUtc,
        TimeZoneInfo timeZone,
        DateTime nowUtc,
        int leadMinutes)
    {
        if (isUserSet)
        {
            return storedLocalTime;
        }

        return DetectWorkoutTime(workoutStartsUtc, timeZone, nowUtc) is TimeSpan detected
            ? WrapDay(detected - TimeSpan.FromMinutes(leadMinutes))
            : storedLocalTime;
    }

    private static IEnumerable<DateTime> Localize(IEnumerable<DateTime> utc, TimeZoneInfo timeZone, DateTime nowUtc)
    {
        var cutoff = nowUtc.AddDays(-LookbackDays);
        return utc
            .Where(t => t >= cutoff && t <= nowUtc)
            .Select(t => UserTimeZoneResolver.ToLocal(t, timeZone));
    }

    private static TimeSpan? Median(List<TimeSpan> times)
    {
        if (times.Count < MinDays)
        {
            return null;
        }

        times.Sort();
        var mid = times.Count / 2;
        var median = times.Count % 2 == 1
            ? times[mid]
            : TimeSpan.FromTicks((times[mid - 1].Ticks + times[mid].Ticks) / 2);

        var minutes = (int)Math.Round(median.TotalMinutes / RoundToMinutes) * RoundToMinutes;
        return WrapDay(TimeSpan.FromMinutes(minutes));
    }

    private static TimeSpan WrapDay(TimeSpan value)
    {
        var day = TimeSpan.FromDays(1);
        var ticks = ((value.Ticks % day.Ticks) + day.Ticks) % day.Ticks;
        return TimeSpan.FromTicks(ticks);
    }
}
