namespace Silen.Common.Exceptions;

public sealed class ValidationException : AppException
{
    public ValidationException(string logMessage, string? userMessage = null)
        : base(400, userMessage ?? logMessage, logMessage)
    {
    }
}
