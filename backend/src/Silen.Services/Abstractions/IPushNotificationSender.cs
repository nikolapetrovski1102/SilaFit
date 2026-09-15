using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>Transport for a single push message to a single device token.</summary>
public interface IPushNotificationSender
{
    /// <summary>
    /// True when a real provider is configured. False routes through the
    /// logging sender, which records what would have been delivered.
    /// </summary>
    bool IsConfigured { get; }

    Task<PushSendResult> SendAsync(PushNotificationMessage message, CancellationToken cancellationToken = default);
}
