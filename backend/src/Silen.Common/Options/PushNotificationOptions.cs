namespace Silen.Common.Options;

/// <summary>
/// Outbound push transport settings (Firebase Cloud Messaging HTTP v1).
/// When disabled - or when no service account is configured - the publisher
/// still composes and stores every notification, and a logging sender records
/// what would have been delivered instead. That mirrors how the monthly review
/// batch behaves when SMTP is unset, and keeps the whole pipeline testable
/// without production credentials.
/// </summary>
public sealed class PushNotificationOptions
{
    public const string SectionName = "Push";

    public bool Enabled { get; set; }

    /// <summary>Firebase project id, used in the FCM v1 send URL.</summary>
    public string ProjectId { get; set; } = string.Empty;

    /// <summary>Service-account JSON contents (inline). Prefer the path below in files.</summary>
    public string ServiceAccountJson { get; set; } = string.Empty;

    /// <summary>Path to a Firebase service-account JSON file.</summary>
    public string ServiceAccountJsonPath { get; set; } = string.Empty;

    public string BaseUrl { get; set; } = "https://fcm.googleapis.com";

    /// <summary>How long FCM should keep retrying a message the device never acknowledged.</summary>
    public int DefaultTtlSeconds { get; set; } = 3600;
}
