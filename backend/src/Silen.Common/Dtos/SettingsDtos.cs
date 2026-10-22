using System.ComponentModel.DataAnnotations;

namespace Silen.Common.Dtos;

public sealed class UpdateUserSettingsRequest
{
    [Range(0, 20000)]
    public int TargetWaterMl { get; set; }

    public bool NotificationsEnabled { get; set; }

    public TimeSpan NotificationLocalTime { get; set; }

    /// <summary>
    /// True when the user picked <see cref="NotificationLocalTime"/> themselves, so
    /// the reminder fires at exactly that time; false switches back to auto-detect.
    /// Null (clients older than this field) keeps the stored flag, except that a
    /// changed time still counts as the user picking it.
    /// </summary>
    public bool? NotificationTimeIsUserSet { get; set; }

    [StringLength(100)]
    public string TimeZoneId { get; set; } = "UTC";

    [StringLength(10)]
    public string WeightUnit { get; set; } = "kg";

    [StringLength(10)]
    public string DistanceUnit { get; set; } = "km";

    public bool RestTimerSoundEnabled { get; set; }

    [StringLength(20)]
    public string AppearanceMode { get; set; } = "Device";

    [StringLength(10)]
    public string AvatarChoice { get; set; } = "Male";
}

public sealed class SetAiDataConsentRequest
{
    public bool Granted { get; set; }
}
