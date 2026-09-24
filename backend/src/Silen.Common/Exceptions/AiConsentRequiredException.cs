namespace Silen.Common.Exceptions;

/// <summary>Thrown when an AI feature would send the user's data to the third-party AI provider before they have consented to it.</summary>
public sealed class AiConsentRequiredException : AppException
{
    public AiConsentRequiredException(string logMessage, string? userMessage = null)
        : base(428, userMessage ?? "Allow AI data sharing in Settings to use AI features.", logMessage)
    {
    }
}
