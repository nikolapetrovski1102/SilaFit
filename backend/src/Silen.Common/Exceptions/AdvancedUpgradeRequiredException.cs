namespace Silen.Common.Exceptions;

/// <summary>Thrown when a Pro-tier (or lower) account requests a feature gated behind an active ADVANCED subscription - currently the weekly AI overview.</summary>
public sealed class AdvancedUpgradeRequiredException : AppException
{
    public AdvancedUpgradeRequiredException(string logMessage, string? userMessage = null)
        : base(403, userMessage ?? "Upgrade to Advanced to unlock your weekly AI overview.", logMessage)
    {
    }
}
