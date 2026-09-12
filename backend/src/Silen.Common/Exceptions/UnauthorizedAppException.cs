namespace Silen.Common.Exceptions;

public sealed class UnauthorizedAppException : AppException
{
    public UnauthorizedAppException(string logMessage, string? userMessage = null)
        : base(401, userMessage ?? "You need to sign in to do that.", logMessage)
    {
    }
}
