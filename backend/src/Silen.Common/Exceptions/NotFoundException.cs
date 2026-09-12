namespace Silen.Common.Exceptions;

public sealed class NotFoundException : AppException
{
    public NotFoundException(string logMessage, string? userMessage = null)
        : base(404, userMessage ?? "We couldn't find what you were looking for.", logMessage)
    {
    }
}
