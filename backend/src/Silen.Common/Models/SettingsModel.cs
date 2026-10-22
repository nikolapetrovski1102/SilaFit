namespace Silen.Common.Models;

public sealed class UserSettingsModel
{
    public Guid UserId { get; set; }
    public int TargetWaterMl { get; set; }
    public bool NotificationsEnabled { get; set; }
    public TimeSpan NotificationLocalTime { get; set; }

    /// <summary>True once the user picked the reminder time; false = auto-detect.</summary>
    public bool NotificationTimeIsUserSet { get; set; }

    /// <summary>
    /// The time the gym reminder will actually fire at in auto mode, learned from
    /// recent workouts; null until there is enough history (the stored 18:00
    /// default applies). Computed by the service, never stored.
    /// </summary>
    public TimeSpan? DetectedNotificationLocalTime { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public IReadOnlyList<DateTime> RecentWorkoutStartsUtc { get; set; } = [];
    public string TimeZoneId { get; set; } = "UTC";
    public string WeightUnit { get; set; } = "kg";
    public string DistanceUnit { get; set; } = "km";
    public bool RestTimerSoundEnabled { get; set; }

    /// <summary>
    /// The barbell-standard setting is gone, but app builds up to 1.0.0 still
    /// read this field as required - keep sending the old default until they age out.
    /// </summary>
    public decimal BarbellStandardKg => 20m;

    public string AppearanceMode { get; set; } = "Device";
    public string AvatarChoice { get; set; } = "Male";

    /// <summary>When the user agreed to share their data with the third-party AI provider; null = not granted.</summary>
    public DateTime? AiDataConsentAtUtc { get; set; }

    public bool AiDataConsent => AiDataConsentAtUtc.HasValue;

    public DateTime UpdatedAtUtc { get; set; }
}
