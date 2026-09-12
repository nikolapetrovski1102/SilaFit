namespace Silen.Common.Exceptions;

/// <summary>
/// Thrown when a Guest-tier account attempts to use a feature that requires a
/// fully linked account (progress tracking, purchases, etc).
/// </summary>
public sealed class AccountRequiredException : AppException
{
    public AccountRequiredException(string logMessage, string? userMessage = null)
        : base(403, userMessage ?? "Create a free account to unlock this feature.", logMessage)
    {
    }
}
