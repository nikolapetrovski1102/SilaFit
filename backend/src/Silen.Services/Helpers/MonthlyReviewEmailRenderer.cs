using System.Globalization;
using System.Net;
using System.Text;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Helpers;

/// <summary>
/// Renders the monthly overview <see cref="MonthlyAnalyticsDto"/> as the HTML
/// email the batch sends. Kept as a standalone outside helper (like the rest of
/// the Helpers/) so the service only orchestrates and this stays unit-testable.
/// All user/AI-authored text is HTML-encoded before it reaches the markup.
/// </summary>
public static class MonthlyReviewEmailRenderer
{
    public static string BuildSubject(MonthlyAnalyticsDto report)
    {
        ArgumentNullException.ThrowIfNull(report);
        return $"Your {PeriodLabel(report)} progress report";
    }

    /// <summary>
    /// Subject for the non-paying teaser. Deliberately frames the month as a
    /// recap (which is real and theirs) while making the locked part explicit,
    /// rather than promising a full report the recipient cannot open yet.
    /// </summary>
    public static string BuildUpsellSubject(int year, int month)
    {
        var label = new DateTime(year, month, 1, 0, 0, 0, DateTimeKind.Utc)
            .ToString("MMMM yyyy", CultureInfo.InvariantCulture);
        return $"Your {label} recap - the full review is one tap away";
    }

    /// <summary>
    /// The non-paying monthly email: the recipient's own free-tier numbers,
    /// then a locked preview of the paid AI sections and an upgrade CTA. No AI
    /// call is made for these, so this costs nothing per recipient and no paid
    /// narrative is included in the markup.
    /// </summary>
    public static string BuildUpsellHtml(
        string? displayName, MonthlySnapshotModel snapshot, int year, int month, string upgradeUrl)
    {
        ArgumentNullException.ThrowIfNull(snapshot);

        var name = string.IsNullOrWhiteSpace(displayName) ? "Athlete" : displayName.Trim();
        var label = new DateTime(year, month, 1, 0, 0, 0, DateTimeKind.Utc)
            .ToString("MMMM yyyy", CultureInfo.InvariantCulture);
        var body = new StringBuilder();

        body.Append("<div style=\"font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;")
            .Append("max-width:600px;margin:0 auto;color:#1f2937;line-height:1.5;\">");
        body.Append($"<h1 style=\"font-size:22px;margin:0 0 4px;\">{Encode(label)} in review</h1>");
        body.Append($"<p style=\"margin:0 0 20px;color:#6b7280;\">Hi {Encode(name)}, here is the month you put in. " +
                    "The coaching read on top of it is part of PRO.</p>");

        body.Append("<h2 style=\"font-size:16px;margin:24px 0 8px;border-bottom:1px solid #e5e7eb;padding-bottom:4px;\">Your month so far</h2>");
        body.Append("<table role=\"presentation\" style=\"width:100%;border-collapse:collapse;font-size:14px;\">");
        body.Append(SummaryRow("Sessions completed", BuildSessions(snapshot)));
        body.Append(SummaryRow("Total tonnage", $"{snapshot.TotalTonnageKg:0.#} kg"));
        body.Append(SummaryRow("Current streak", $"{snapshot.CurrentStreakDays} day(s)"));
        body.Append(SummaryRow("Nutrition adherence", BuildNutritionAdherence(snapshot)));
        body.Append("</table>");

        // The locked block names exactly what the paid report adds, so the CTA
        // reads as "here is what you are missing" rather than a vague nudge.
        body.Append("<div style=\"margin:24px 0;padding:16px;border:1px dashed #d1d5db;border-radius:12px;background:#f9fafb;\">");
        body.Append("<p style=\"margin:0 0 8px;font-weight:600;\">🔒 Locked in your PRO review</p>");
        body.Append("<ul style=\"margin:0;padding-left:20px;font-size:14px;color:#6b7280;\">");
        body.Append("<li style=\"margin-bottom:6px;\"><strong style=\"color:#1f2937;\">What improved</strong> - the wins the numbers show</li>");
        body.Append("<li style=\"margin-bottom:6px;\"><strong style=\"color:#1f2937;\">What to improve</strong> - ranked, with what to change</li>");
        body.Append("<li style=\"margin-bottom:6px;\"><strong style=\"color:#1f2937;\">How to continue</strong> - your focus for next month</li>");
        body.Append("</ul>");
        body.Append("</div>");

        body.Append("<p style=\"margin:0 0 20px;font-size:14px;\">Your AI coach already has the numbers above. " +
                    "Unlock PRO to read the full review written from them.</p>");

        if (!string.IsNullOrWhiteSpace(upgradeUrl))
        {
            body.Append($"<p style=\"margin:0 0 28px;\"><a href=\"{Encode(upgradeUrl)}\" ")
                .Append("style=\"display:inline-block;background:#111827;color:#ffffff;text-decoration:none;")
                .Append("padding:12px 22px;border-radius:999px;font-weight:600;font-size:14px;\">Unlock your full review</a></p>");
        }

        body.Append("<p style=\"margin:0;font-size:12px;color:#9ca3af;\">You are getting this because you have a SilaFit account. ")
            .Append("Keep training.</p>");
        body.Append("</div>");

        return body.ToString();
    }

    public static string BuildHtml(string? displayName, MonthlyAnalyticsDto report)
    {
        ArgumentNullException.ThrowIfNull(report);

        var name = string.IsNullOrWhiteSpace(displayName) ? "Athlete" : displayName.Trim();
        var summary = report.Summary;
        var body = new StringBuilder();

        body.Append("<div style=\"font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;")
            .Append("max-width:600px;margin:0 auto;color:#1f2937;line-height:1.5;\">");
        body.Append($"<h1 style=\"font-size:22px;margin:0 0 4px;\">Your {Encode(PeriodLabel(report))} progress report</h1>");
        body.Append($"<p style=\"margin:0 0 20px;color:#6b7280;\">Hi {Encode(name)}, here is how your month went and what to focus on next.</p>");

        body.Append("<h2 style=\"font-size:16px;margin:24px 0 8px;border-bottom:1px solid #e5e7eb;padding-bottom:4px;\">At a glance</h2>");
        body.Append("<table role=\"presentation\" style=\"width:100%;border-collapse:collapse;font-size:14px;\">");
        body.Append(SummaryRow("Sessions completed", $"{summary.CompletedSessions} of {summary.ScheduledSessions} scheduled"));
        body.Append(SummaryRow("Total tonnage", $"{summary.TotalTonnageKg:0.#} kg"));
        body.Append(SummaryRow("Average session RPE", summary.AvgRpe.ToString("0.#", CultureInfo.InvariantCulture)));
        body.Append(SummaryRow("Current streak", $"{summary.CurrentStreakDays} day(s)"));
        body.Append(SummaryRow("This week's compliance", $"{summary.WeeklyCompliancePercent}%"));
        body.Append(SummaryRow("Bodyweight trend", BuildWeightTrend(summary)));
        body.Append(SummaryRow("Nutrition adherence", BuildNutritionAdherence(summary)));
        body.Append("</table>");

        if (report.Strengths.Count > 0)
        {
            body.Append("<h2 style=\"font-size:16px;margin:24px 0 8px;border-bottom:1px solid #e5e7eb;padding-bottom:4px;\">What improved</h2>");
            body.Append("<ul style=\"margin:0;padding-left:20px;font-size:14px;\">");
            foreach (var strength in report.Strengths)
            {
                body.Append($"<li style=\"margin-bottom:6px;\">{Encode(strength)}</li>");
            }

            body.Append("</ul>");
        }

        if (report.Improvements.Count > 0)
        {
            body.Append("<h2 style=\"font-size:16px;margin:24px 0 8px;border-bottom:1px solid #e5e7eb;padding-bottom:4px;\">What to improve</h2>");
            body.Append("<ul style=\"margin:0;padding-left:20px;font-size:14px;\">");
            foreach (var improvement in report.Improvements)
            {
                body.Append("<li style=\"margin-bottom:8px;\">")
                    .Append($"<strong>{Encode(improvement.Area)}</strong> ")
                    .Append($"<span style=\"color:#6b7280;\">({Encode(improvement.Priority)} priority)</span><br/>")
                    .Append(Encode(improvement.Recommendation))
                    .Append("</li>");
            }

            body.Append("</ul>");
        }

        if (!string.IsNullOrWhiteSpace(report.FocusForNextMonth))
        {
            body.Append("<h2 style=\"font-size:16px;margin:24px 0 8px;border-bottom:1px solid #e5e7eb;padding-bottom:4px;\">How to continue</h2>");
            body.Append("<p style=\"margin:0;font-size:14px;\">").Append(Encode(report.FocusForNextMonth)).Append("</p>");
        }

        body.Append("<p style=\"margin:28px 0 0;font-size:12px;color:#9ca3af;\">Generated by SilaFit on ")
            .Append(report.GeneratedAtUtc.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture))
            .Append(". Keep training.</p>");
        body.Append("</div>");

        return body.ToString();
    }

    private static string PeriodLabel(MonthlyAnalyticsDto report) =>
        new DateTime(report.Year, report.Month, 1, 0, 0, 0, DateTimeKind.Utc).ToString("MMMM yyyy", CultureInfo.InvariantCulture);

    private static string SummaryRow(string label, string value) =>
        $"<tr><td style=\"padding:4px 0;color:#6b7280;width:60%;\">{Encode(label)}</td>" +
        $"<td style=\"padding:4px 0;text-align:right;font-weight:600;\">{Encode(value)}</td></tr>";

    private static string BuildSessions(MonthlySnapshotModel snapshot) =>
        snapshot.ScheduledSessions > 0
            ? $"{snapshot.CompletedSessions} of {snapshot.ScheduledSessions} scheduled"
            : $"{snapshot.CompletedSessions} logged";

    private static string BuildNutritionAdherence(MonthlySnapshotModel snapshot) =>
        snapshot.LoggedMealDays == 0
            ? "No nutrition logs recorded"
            : $"{snapshot.LoggedMealDays} of {snapshot.TotalDaysInRange} days logged";

    private static string BuildWeightTrend(MonthlyAnalyticsSummaryDto summary)
    {
        if (summary.StartWeightKg is not { } start || summary.EndWeightKg is not { } end)
        {
            return "No bodyweight logs recorded";
        }

        var delta = end - start;
        if (delta == 0)
        {
            return $"{start:0.#} kg (unchanged)";
        }

        var direction = delta > 0 ? "up" : "down";
        return $"{start:0.#} kg to {end:0.#} kg ({direction} {Math.Abs(delta):0.#} kg)";
    }

    private static string BuildNutritionAdherence(MonthlyAnalyticsSummaryDto summary)
    {
        // TotalDaysInRange is always the length of the reported month (28-31), so the only
        // way there is no nutrition data to show is when no meal was logged at all.
        if (summary.LoggedMealDays == 0)
        {
            return "No nutrition logs recorded";
        }

        return $"{summary.LoggedMealDays} of {summary.TotalDaysInRange} days logged";
    }

    private static string Encode(string value) => WebUtility.HtmlEncode(value);
}
