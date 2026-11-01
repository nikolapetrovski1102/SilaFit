using Silen.Services.Helpers;

namespace Silen.Tests.Helpers;

public sealed class DietPlanRotationTests
{
    // 2026-11-04 is a Wednesday; its week starts Monday 2026-11-02.
    private static readonly DateOnly ActivatedWednesday = new(2026, 11, 4);

    [Theory]
    [InlineData(2026, 11, 2, 1)] // Monday of the activation week
    [InlineData(2026, 11, 4, 3)] // activation day itself picks up at its weekday
    [InlineData(2026, 11, 8, 7)] // Sunday
    [InlineData(2026, 11, 9, 1)] // next Monday loops back for a one-week plan
    public void SevenDayPlan_FollowsTheWeekday(int y, int m, int d, int expected) =>
        Assert.Equal(expected, DietPlanRotation.DayIndexFor(new DateOnly(y, m, d), ActivatedWednesday, 7, 7));

    [Fact]
    public void MultiWeekPlan_AdvancesEachMondayAndLoops()
    {
        // A 3-week trainer plan: week 2 starts the second Monday, week 1 returns after week 3.
        Assert.Equal(8, DietPlanRotation.DayIndexFor(new DateOnly(2026, 11, 9), ActivatedWednesday, 21, 21));
        Assert.Equal(21, DietPlanRotation.DayIndexFor(new DateOnly(2026, 11, 22), ActivatedWednesday, 21, 21));
        Assert.Equal(1, DietPlanRotation.DayIndexFor(new DateOnly(2026, 11, 23), ActivatedWednesday, 21, 21));
    }

    [Fact]
    public void CycleLength_CoversDurationAndHighestDay_InWholeWeeks()
    {
        Assert.Equal(7, DietPlanRotation.CycleLength(5, 5));
        Assert.Equal(35, DietPlanRotation.CycleLength(30, 30));
        Assert.Equal(14, DietPlanRotation.CycleLength(7, 10));
        Assert.Equal(182, DietPlanRotation.CycleLength(182, 182));
    }

    [Fact]
    public void PickDay_MissingSlot_FallsBackToSameWeekdayInWeekOne()
    {
        var days = Enumerable.Range(1, 30).Select(i => new Day(i)).ToList();

        Assert.Equal(12, DietPlanRotation.PickDay(days, 12, x => x.Index)!.Index);
        Assert.Equal(3, DietPlanRotation.PickDay(days, 31, x => x.Index)!.Index); // day 31 = week 5 Wednesday → week 1 Wednesday
        Assert.Null(DietPlanRotation.PickDay(new List<Day>(), 1, x => x.Index));
        Assert.Equal(2, DietPlanRotation.PickDay(new List<Day> { new(4), new(2) }, 6, x => x.Index)!.Index);
    }

    private sealed record Day(int Index);
}
