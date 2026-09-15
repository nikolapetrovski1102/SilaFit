using System.ComponentModel.DataAnnotations;

namespace Silen.Common.Dtos;

public sealed class UpdateUserSettingsRequest
{
    [Range(0, 20000)]
    public int TargetWaterMl { get; set; }

    public bool NotificationsEnabled { get; set; }

    public TimeSpan NotificationLocalTime { get; set; }

    [StringLength(100)]
    public string TimeZoneId { get; set; } = "UTC";

    [StringLength(10)]
    public string WeightUnit { get; set; } = "kg";

    [StringLength(10)]
    public string DistanceUnit { get; set; } = "km";

    public bool RestTimerSoundEnabled { get; set; }

    [Range(0, 500)]
    public decimal BarbellStandardKg { get; set; }

    [StringLength(20)]
    public string AppearanceMode { get; set; } = "Device";
}
