namespace Silen.Common.Exceptions;

/// <summary>
/// Thrown when an account is temporarily locked after too many failed attempts.
/// Distinct from <see cref="UnauthorizedAppException"/> so the console can say
/// "locked, try again in N minutes" instead of implying the password was wrong -
/// and so nginx/any future rate limiter can treat 429 differently from 401.
/// </summary>
public sealed class TooManyRequestsException : AppException
{
    public TooManyRequestsException(string logMessage, string? userMessage = null)
        : base(429, userMessage ?? "Too many attempts. Please try again later.", logMessage)
    {
    }
}
