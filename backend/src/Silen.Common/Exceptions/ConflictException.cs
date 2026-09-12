namespace Silen.Common.Exceptions;

public sealed class ConflictException : AppException
{
    public ConflictException(string logMessage, string? userMessage = null)
        : base(409, userMessage ?? logMessage, logMessage)
    {
    }
}
