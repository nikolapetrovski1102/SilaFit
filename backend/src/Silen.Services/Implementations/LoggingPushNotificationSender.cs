using Microsoft.Extensions.Logging;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <summary>
/// Fallback transport used when no FCM service account is configured. It does
/// not deliver anything; it logs the composed message and reports success so
/// the outbox still records exactly what the publisher decided. This keeps the
/// pipeline (scheduling, dedupe, message copy) fully exercisable in local dev
/// and in a deployment that has not wired Firebase yet.
/// </summary>
public sealed class LoggingPushNotificationSender(ILogger<LoggingPushNotificationSender> logger) : IPushNotificationSender
{
    public bool IsConfigured => false;

    public Task<PushSendResult> SendAsync(PushNotificationMessage message, CancellationToken cancellationToken = default)
    {
        // Only the one-way token tag and the title are logged: the full token is a
        // capability, and the body carries the user's name/greeting.
        logger.LogInformation(
            "[push:log-only] tokenTag={TokenTag} title='{Title}'",
            LogRedaction.Tag(message.Token),
            message.Title);

        return Task.FromResult(PushSendResult.Sent($"log-only:{Guid.NewGuid():N}"));
    }
}
