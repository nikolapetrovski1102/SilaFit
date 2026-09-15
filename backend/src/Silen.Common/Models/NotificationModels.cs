namespace Silen.Common.Models;

/// <summary>
/// The notification categories the publisher knows how to compose. Kept as
/// constants (rather than an enum) because they are persisted and checked in
/// SQL, and surfaced verbatim to the client as the push `data.category`.
/// </summary>
public static class NotificationCategories
{
    public const string GymReminder = "GymReminder";
    public const string TrackSets = "TrackSets";
    public const string TrackCalories = "TrackCalories";
    public const string MealIdea = "MealIdea";
    public const string Motivation = "Motivation";
    public const string Comeback = "Comeback";

    /// <summary>Monthly "your full review is locked, upgrade" nudge for non-paying users.</summary>
    public const string MonthlyReviewUpsell = "MonthlyReviewUpsell";

    public static bool IsValid(string category) => category switch
    {
        GymReminder or TrackSets or TrackCalories or MealIdea or Motivation or Comeback or MonthlyReviewUpsell => true,
        _ => false
    };
}

/// <summary>A registered push token for one user install.</summary>
public sealed class UserDeviceTokenModel
{
    public Guid DeviceTokenId { get; set; }
    public Guid UserId { get; set; }
    public string Platform { get; set; } = "unknown";
    public string PushToken { get; set; } = string.Empty;
    public string? TimeZoneId { get; set; }
    public bool IsActive { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public DateTime UpdatedAtUtc { get; set; }
    public DateTime LastSeenAtUtc { get; set; }
}

/// <summary>
/// One opted-in user plus the raw UTC facts the scheduler needs. Deliberately
/// not pre-decided in SQL: local-time windows depend on the user's timezone, so
/// the decision lives in the service where timezone conversion is available.
/// </summary>
public sealed class NotificationCandidateModel
{
    public Guid UserId { get; set; }
    public string? DisplayName { get; set; }
    public bool NotificationsEnabled { get; set; }
    public TimeSpan NotificationLocalTime { get; set; }
    public string TimeZoneId { get; set; } = "UTC";

    public DateTime? LastInteractionAtUtc { get; set; }
    public DateTime? LastPushedAtUtc { get; set; }
    public DateTime? LastMotivationAtUtc { get; set; }
    public DateTime? LastComebackAtUtc { get; set; }
    public int SentLast24h { get; set; }

    public DateTime? LastWorkoutStartedAtUtc { get; set; }
    public DateTime? LastWorkoutCompletedAtUtc { get; set; }
    public int WorkoutsLast7Days { get; set; }

    public DateTime? ActiveSessionStartedAtUtc { get; set; }
    public DateTime? ActiveSessionLastActivityAtUtc { get; set; }

    public DateTime? LastMealLoggedAtUtc { get; set; }
    public int MealsLast24h { get; set; }

    /// <summary>True when the user holds an active PRO/ADVANCED entitlement - the
    /// monthly review upsell is only for users who do not.</summary>
    public bool HasPaidSubscription { get; set; }

    public int ActiveTokenCount { get; set; }
}

/// <summary>A row in dbo.UserNotifications - the outbox/audit entry.</summary>
public sealed class UserNotificationModel
{
    public Guid NotificationId { get; set; }
    public Guid UserId { get; set; }
    public string Category { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public string? DeepLink { get; set; }
    public string DedupeKey { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string? ProviderMessageId { get; set; }
    public string? ErrorMessage { get; set; }
    public DateTime? ScheduledLocalAt { get; set; }
    public DateTime? SentAtUtc { get; set; }
    public DateTime? OpenedAtUtc { get; set; }
    public DateTime CreatedAtUtc { get; set; }
}

/// <summary>The payload the service hands to the provider to enqueue.</summary>
public sealed class NewNotificationModel
{
    public Guid UserId { get; set; }
    public string Category { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public string? DeepLink { get; set; }
    public string DedupeKey { get; set; } = string.Empty;
    public DateTime? ScheduledLocalAt { get; set; }
}

/// <summary>A composed message ready for one push token.</summary>
public sealed class PushNotificationMessage
{
    public string Token { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public IReadOnlyDictionary<string, string> Data { get; set; } = new Dictionary<string, string>();
    public int? TtlSeconds { get; set; }
}

/// <summary>Outcome of sending one message to one token.</summary>
public sealed class PushSendResult
{
    public bool Success { get; init; }
    public string? ProviderMessageId { get; init; }
    public string? Error { get; init; }

    /// <summary>True when the provider says this token can never work again - deactivate it.</summary>
    public bool TokenInvalid { get; init; }

    public static PushSendResult Sent(string? providerMessageId = null) => new()
    {
        Success = true,
        ProviderMessageId = providerMessageId
    };

    public static PushSendResult Failed(string error, bool tokenInvalid = false) => new()
    {
        Success = false,
        Error = error,
        TokenInvalid = tokenInvalid
    };
}
