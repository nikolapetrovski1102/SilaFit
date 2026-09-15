using System.ComponentModel.DataAnnotations;

namespace Silen.Common.Dtos;

/// <summary>
/// Sent by the app as soon as the notification permission prompt is answered,
/// and again whenever the OS hands back a push token (or the device timezone
/// changes). Both the token and the timezone are optional so either half can be
/// persisted on its own.
/// </summary>
public sealed class RegisterDeviceTokenRequest
{
    [StringLength(4096)]
    public string? Token { get; set; }

    [StringLength(32)]
    public string Platform { get; set; } = "unknown";

    /// <summary>
    /// IANA id ("Europe/Skopje"), Windows id ("Central European Standard Time"),
    /// or a fixed offset ("+02:00"). The server normalizes and stores it.
    /// </summary>
    [StringLength(100)]
    public string? TimeZoneId { get; set; }

    public bool? NotificationsEnabled { get; set; }
}

public sealed class DeactivateDeviceTokenRequest
{
    [Required]
    [StringLength(4096, MinimumLength = 1)]
    public string Token { get; set; } = string.Empty;
}

/// <summary>
/// "The user used the app" signal - sent on cold start/resume, and again when a
/// notification is tapped. Drives the quiet-then-comeback backoff.
/// </summary>
public sealed class RecordNotificationInteractionRequest
{
    public Guid? NotificationId { get; set; }

    [StringLength(100)]
    public string? TimeZoneId { get; set; }
}

/// <summary>
/// "I'm still in the gym" ping from the Active Workout Tracker. Fired while a
/// session is open so the server can time a set-logging nudge.
/// </summary>
public sealed class WorkoutHeartbeatRequest
{
    public Guid? WorkoutSessionId { get; set; }
}

/// <summary>Result of one publish run, printed by the cron tool and returned for observability.</summary>
public sealed class NotificationPublishSummaryDto
{
    public bool DryRun { get; set; }
    public bool PushConfigured { get; set; }
    public int CandidatesConsidered { get; set; }
    public int WouldSend { get; set; }
    public int Created { get; set; }
    public int Sent { get; set; }
    public int Failed { get; set; }
    public int Skipped { get; set; }
    public int Suppressed { get; set; }

    /// <summary>
    /// Pending-flush counters (see "Pending flush" in deploy/README.md): rows a
    /// previous run left in 'Created' that this run retried.
    /// </summary>
    public int PendingConsidered { get; set; }
    public int PendingSent { get; set; }
    public int PendingFailed { get; set; }
    public int PendingSkipped { get; set; }

    public List<NotificationPublishFailureDto> Failures { get; set; } = new();
    public DateTime StartedAtUtc { get; set; }
    public DateTime CompletedAtUtc { get; set; }
}

public sealed class NotificationPublishFailureDto
{
    public Guid UserId { get; set; }
    public string Category { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
}
