namespace Silen.Common.Exceptions;

/// <summary>Thrown when a caller's plan entitlements refuse the action - too many
/// active splits/diet plans for their tier, or AI generation not included.</summary>
public sealed class PlanLimitExceededException : AppException
{
    public PlanLimitExceededException(string logMessage, string? userMessage = null)
        : base(403, userMessage ?? "You've reached your plan's limit. Upgrade to add more.", logMessage)
    {
    }
}
