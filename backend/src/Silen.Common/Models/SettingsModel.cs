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
    public string AvatarChoice { get; set; } = "Male";

    /// <summary>When the user agreed to share their data with the third-party AI provider; null = not granted.</summary>
    public DateTime? AiDataConsentAtUtc { get; set; }

    public bool AiDataConsent => AiDataConsentAtUtc.HasValue;

    public DateTime UpdatedAtUtc { get; set; }
}
