namespace Silen.Services.Helpers;

/// <summary>
/// Which plan day an active diet plan serves on a date. Same rotation as splits
/// (usp_WorkoutSession_GetTodayScheduled): anchored to the Monday of the week the
/// plan was activated, whole weeks long (covering both the plan's duration and its
/// highest authored day), and looping back to week 1 after the last week. A 7-day
/// plan therefore maps Monday..Sunday onto days 1..7, and a 12-week trainer plan
/// moves on a week every Monday.
///
/// Mirrored by <c>dietPlanDayIndexFor</c> in the app's diet_plan_models.dart, so the
/// Planned logs written on activation match what the Nutrition screen shows.
/// </summary>
public static class DietPlanRotation
{
    public static int CycleLength(int durationDays, int maxDayIndex)
    {
        var span = Math.Max(1, Math.Max(durationDays, maxDayIndex));
        return (int)Math.Ceiling(span / 7.0) * 7;
    }

    /// <summary>1-based position in the cycle for <paramref name="date"/>.</summary>
    public static int DayIndexFor(DateOnly date, DateOnly activatedOn, int durationDays, int maxDayIndex)
    {
        var anchor = MondayOf(activatedOn);
        var cycle = CycleLength(durationDays, maxDayIndex);
        var offset = date.DayNumber - anchor.DayNumber;
        return ((offset % cycle) + cycle) % cycle + 1;
    }

    /// <summary>The authored day for a cycle slot. A slot nobody wrote a day for (the
    /// tail of a 30-day plan's fifth week, say) falls back to the same weekday in
    /// week 1, then to the first day.</summary>
    public static T? PickDay<T>(IReadOnlyList<T> days, int dayIndex, Func<T, int> indexOf) where T : class
    {
        if (days.Count == 0)
        {
            return null;
        }

        var weekday = ((dayIndex - 1) % 7) + 1;
        return days.FirstOrDefault(d => indexOf(d) == dayIndex)
            ?? days.FirstOrDefault(d => indexOf(d) == weekday)
            ?? days.OrderBy(indexOf).First();
    }

    public static DateOnly MondayOf(DateOnly date)
    {
        var daysSinceMonday = ((int)date.DayOfWeek + 6) % 7;
        return date.AddDays(-daysSinceMonday);
    }
}
