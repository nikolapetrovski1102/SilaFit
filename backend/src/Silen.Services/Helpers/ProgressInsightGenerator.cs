using Silen.Common.Models;

namespace Silen.Services.Helpers;

/// <summary>
/// Rule-based "AI" narrative for the Progress screen: real numbers in, plain
/// template sentences out. No external LLM call, no extra cost/dependency -
/// kept as an outside helper so ProgressService has no private methods.
/// </summary>
public static class ProgressInsightGenerator
{
    public static List<string> Generate(RangeSummaryModel summary, StreakStatusModel streak)
    {
        var insights = new List<string>();

        insights.Add(streak.CurrentStreakDays switch
        {
            0 => "No active streak yet - complete today's session to start one.",
            1 => "You're 1 day into a new streak. Keep the momentum going tomorrow.",
            < 7 => $"You're on a {streak.CurrentStreakDays}-day streak. A full week is within reach.",
            _ => $"Strong consistency: a {streak.CurrentStreakDays}-day streak and counting."
        });

        insights.Add(streak.WeeklyCompliancePercent switch
        {
            >= 90 => $"You hit {streak.WeeklyCompliancePercent}% of this week's planned sessions - excellent adherence.",
            >= 60 => $"You're at {streak.WeeklyCompliancePercent}% compliance this week. A couple more sessions closes the gap.",
            _ => $"Compliance is at {streak.WeeklyCompliancePercent}% this week. Consider a lighter, more achievable session to rebuild momentum."
        });

        if (summary.ScheduledSessions > 0)
        {
            var completionRate = (int)Math.Round(100.0 * summary.CompletedSessions / summary.ScheduledSessions);
            insights.Add($"You completed {summary.CompletedSessions} of {summary.ScheduledSessions} scheduled sessions ({completionRate}%) in this period.");
        }

        if (summary.TotalTonnageKg > 0)
        {
            insights.Add($"Total volume moved: {summary.TotalTonnageKg:N0} kg across completed sessions.");
        }

        if (summary.AvgRpe > 0)
        {
            insights.Add(summary.AvgRpe switch
            {
                >= 8.5m => $"Average RPE is {summary.AvgRpe:N1} - sessions are running hard. Consider a deload week soon.",
                >= 6m => $"Average RPE is {summary.AvgRpe:N1} - a solid, sustainable training intensity.",
                _ => $"Average RPE is {summary.AvgRpe:N1} - there's room to push intensity a little harder."
            });
        }

        return insights;
    }
}
