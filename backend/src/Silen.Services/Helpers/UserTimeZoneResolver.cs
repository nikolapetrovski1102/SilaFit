using System.Globalization;
using System.Text.RegularExpressions;

namespace Silen.Services.Helpers;

/// <summary>
/// Turns whatever the app stored as a timezone into a real
/// <see cref="TimeZoneInfo"/>. Accepts IANA ids ("Europe/Skopje"), Windows ids
/// ("Central European Standard Time"), and fixed offsets ("+02:00") so a client
/// that cannot resolve an IANA id (Flutter has no built-in zone database) still
/// gets correctly-timed reminders.
/// </summary>
public static partial class UserTimeZoneResolver
{
    private static readonly Regex OffsetPattern = BuildOffsetPattern();

    /// <summary>Never throws - an unknown/blank id falls back to UTC.</summary>
    public static TimeZoneInfo Resolve(string? timeZoneId) =>
        TryNormalize(timeZoneId, out _, out var timeZone) ? timeZone : TimeZoneInfo.Utc;

    public static DateTime ToLocal(DateTime utc, TimeZoneInfo timeZone)
    {
        var kinded = utc.Kind == DateTimeKind.Utc ? utc : DateTime.SpecifyKind(utc, DateTimeKind.Utc);
        return TimeZoneInfo.ConvertTimeFromUtc(kinded, timeZone);
    }

    /// <summary>Midnight of the user's current local day, in UTC - when a daily allowance resets.</summary>
    public static DateTime LocalDayStartUtc(string? timeZoneId, DateTime utcNow)
    {
        var timeZone = Resolve(timeZoneId);
        var localMidnight = DateTime.SpecifyKind(ToLocal(utcNow, timeZone).Date, DateTimeKind.Unspecified);

        // A zone whose DST jump skips midnight has no 00:00 that day; the day starts at the jump.
        while (timeZone.IsInvalidTime(localMidnight))
        {
            localMidnight = localMidnight.AddMinutes(30);
        }

        return TimeZoneInfo.ConvertTimeToUtc(localMidnight, timeZone);
    }

    /// <summary>
    /// Validates and canonicalizes a client-supplied timezone. Fixed offsets are
    /// rewritten to "+HH:MM"; named zones are kept as-is once .NET recognizes them.
    /// </summary>
    public static bool TryNormalize(string? value, out string normalized, out TimeZoneInfo timeZone)
    {
        normalized = "UTC";
        timeZone = TimeZoneInfo.Utc;

        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var candidate = value.Trim();

        if (OffsetPattern.Match(candidate) is { Success: true } match)
        {
            var sign = match.Groups[1].Value == "-" ? -1 : 1;
            var hours = int.Parse(match.Groups[2].Value, CultureInfo.InvariantCulture);
            var minutes = int.Parse(match.Groups[3].Value, CultureInfo.InvariantCulture);
            var offset = TimeSpan.FromMinutes(sign * (hours * 60 + minutes));

            if (hours > 14 || minutes > 59 || offset.Duration() > TimeSpan.FromHours(14))
            {
                return false;
            }

            normalized = $"{sign:+;-}{hours:00}:{minutes:00}";
            timeZone = TimeZoneInfo.CreateCustomTimeZone($"Silen_{normalized}", offset, normalized, normalized);
            return true;
        }

        try
        {
            timeZone = TimeZoneInfo.FindSystemTimeZoneById(candidate);
            normalized = candidate;
            return true;
        }
        catch (TimeZoneNotFoundException)
        {
            return false;
        }
        catch (InvalidTimeZoneException)
        {
            return false;
        }
    }

    [GeneratedRegex(@"^([+-])(\d{1,2}):?(\d{2})$")]
    private static partial Regex BuildOffsetPattern();
}
