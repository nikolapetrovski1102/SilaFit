namespace Silen.Common.Models;

public sealed class UserSettingsModel
{
    public Guid UserId { get; set; }
    public int TargetWaterMl { get; set; }
    public bool NotificationsEnabled { get; set; }
    public TimeSpan NotificationLocalTime { get; set; }
    public string TimeZoneId { get; set; } = "UTC";
    public string WeightUnit { get; set; } = "kg";
    public string DistanceUnit { get; set; } = "km";
    public bool RestTimerSoundEnabled { get; set; }
    public decimal BarbellStandardKg { get; set; }
    public string AppearanceMode { get; set; } = "Device";

    /// <summary>Whether the Sunday batch (<c>IWeeklyPlanGenerationService</c>) considers this user at all.</summary>
    public bool ReceiveWeeklyAiPlans { get; set; }

    /// <summary>Whether each newly generated split/diet plan becomes active automatically, or just lands in the user's list.</summary>
    public bool AutoActivateAiPlans { get; set; }

    public DateTime UpdatedAtUtc { get; set; }
}
