namespace Silen.Common.Exceptions;

/// <summary>Thrown when a Free-tier (or expired) account requests a feature gated behind an active Pro/Advanced subscription.</summary>
public sealed class ProUpgradeRequiredException : AppException
{
    public ProUpgradeRequiredException(string logMessage, string? userMessage = null)
        : base(403, userMessage ?? "Upgrade to Pro to unlock AI insights.", logMessage)
    {
    }
}
