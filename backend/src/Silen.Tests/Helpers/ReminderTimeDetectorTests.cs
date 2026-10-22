using Silen.Services.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class ReminderTimeDetectorTests
{
    private static readonly DateTime Now = new(2026, 10, 16, 12, 0, 0, DateTimeKind.Utc);
    private static readonly TimeSpan Default = TimeSpan.FromHours(18);

    private static DateTime DaysAgoAt(int days, int hour, int minute) =>
        Now.Date.AddDays(-days).AddHours(hour).AddMinutes(minute);

    [Fact]
    public void DetectWorkoutTime_TooFewDays_ReturnsNull()
    {
        var starts = new[] { DaysAgoAt(1, 7, 0), DaysAgoAt(2, 7, 0) };

        Assert.Null(ReminderTimeDetector.DetectWorkoutTime(starts, TimeZoneInfo.Utc, Now));
    }

    [Fact]
    public void DetectWorkoutTime_ReturnsMedianRoundedToFiveMinutes()
    {
        var starts = new[] { DaysAgoAt(1, 6, 52), DaysAgoAt(3, 7, 4), DaysAgoAt(5, 7, 31) };

        Assert.Equal(new TimeSpan(7, 5, 0), ReminderTimeDetector.DetectWorkoutTime(starts, TimeZoneInfo.Utc, Now));
    }

    [Fact]
    public void DetectWorkoutTime_CountsOnlyFirstSessionPerDay()
    {
        // Three days of 07:00 training; an evening double-session must not pull the median.
        var starts = new[]
        {
            DaysAgoAt(1, 7, 0), DaysAgoAt(1, 19, 0),
            DaysAgoAt(2, 7, 0), DaysAgoAt(2, 19, 0),
            DaysAgoAt(3, 7, 0)
        };

        Assert.Equal(new TimeSpan(7, 0, 0), ReminderTimeDetector.DetectWorkoutTime(starts, TimeZoneInfo.Utc, Now));
    }

    [Fact]
    public void DetectWorkoutTime_IgnoresHistoryOutsideLookback()
    {
        var starts = new[] { DaysAgoAt(40, 7, 0), DaysAgoAt(41, 7, 0), DaysAgoAt(42, 7, 0) };

        Assert.Null(ReminderTimeDetector.DetectWorkoutTime(starts, TimeZoneInfo.Utc, Now));
    }

    [Fact]
    public void DetectWorkoutTime_UsesUsersTimeZone()
    {
        // 15:00 UTC is 17:00 at +02:00.
        var starts = new[] { DaysAgoAt(1, 15, 0), DaysAgoAt(2, 15, 0), DaysAgoAt(3, 15, 0) };
        var zone = UserTimeZoneResolver.Resolve("+02:00");

        Assert.Equal(new TimeSpan(17, 0, 0), ReminderTimeDetector.DetectWorkoutTime(starts, zone, Now));
    }

    [Fact]
    public void GymReminderTime_UserSet_IsFollowedExactlyEvenWithHistory()
    {
        var starts = new[] { DaysAgoAt(1, 7, 0), DaysAgoAt(2, 7, 0), DaysAgoAt(3, 7, 0) };
        var picked = new TimeSpan(20, 15, 0);

        Assert.Equal(picked, ReminderTimeDetector.GymReminderTime(picked, true, starts, TimeZoneInfo.Utc, Now, 30));
    }

    [Fact]
    public void GymReminderTime_AutoWithoutHistory_FallsBackToDefault()
    {
        Assert.Equal(Default, ReminderTimeDetector.GymReminderTime(Default, false, [], TimeZoneInfo.Utc, Now, 30));
    }

    [Fact]
    public void GymReminderTime_AutoWithHistory_FiresLeadMinutesBeforeUsualTime()
    {
        var starts = new[] { DaysAgoAt(1, 7, 0), DaysAgoAt(2, 7, 0), DaysAgoAt(3, 7, 0) };

        Assert.Equal(new TimeSpan(6, 30, 0), ReminderTimeDetector.GymReminderTime(Default, false, starts, TimeZoneInfo.Utc, Now, 30));
    }

    [Fact]
    public void DetectMealTime_OnlyCountsLogsNearTheSlot()
    {
        var lunch = new TimeSpan(12, 30, 0);
        var logs = new[]
        {
            DaysAgoAt(1, 8, 0), DaysAgoAt(1, 13, 10),
            DaysAgoAt(2, 8, 0), DaysAgoAt(2, 13, 20),
            DaysAgoAt(3, 8, 0), DaysAgoAt(3, 13, 30)
        };

        Assert.Equal(new TimeSpan(13, 20, 0), ReminderTimeDetector.DetectMealTime(logs, TimeZoneInfo.Utc, Now, lunch));
    }

    [Fact]
    public void DetectMealTime_NoRoutineNearSlot_ReturnsNull()
    {
        var logs = new[] { DaysAgoAt(1, 8, 0), DaysAgoAt(2, 8, 0), DaysAgoAt(3, 8, 0) };

        Assert.Null(ReminderTimeDetector.DetectMealTime(logs, TimeZoneInfo.Utc, Now, new TimeSpan(12, 30, 0)));
    }
}
