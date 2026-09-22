namespace Silen.Common.Dtos;

/// <summary>Body of an App Store Server Notifications V2 call - a single JWS
/// wrapping the actual notification payload.</summary>
public sealed class AppleServerNotificationRequest
{
    public string SignedPayload { get; set; } = string.Empty;
}

/// <summary>Google Cloud Pub/Sub push envelope - what Play's Real-time Developer
/// Notifications topic delivers a push subscription.</summary>
public sealed class PubSubPushEnvelope
{
    public PubSubMessage? Message { get; set; }
}

public sealed class PubSubMessage
{
    /// <summary>Base64-encoded JSON body (a DeveloperNotification).</summary>
    public string? Data { get; set; }
}
