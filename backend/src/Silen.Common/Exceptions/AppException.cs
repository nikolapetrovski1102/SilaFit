namespace Silen.Common.Exceptions;

/// <summary>
/// Base type for every exception the service layer is allowed to throw on
/// purpose. It always carries a safe, user-facing message separately from the
/// detailed message that goes to the logs, plus the HTTP status code the API
/// layer should map it to.
/// </summary>
public abstract class AppException : Exception
{
    public int StatusCode { get; }

    public string UserMessage { get; }

    protected AppException(int statusCode, string userMessage, string logMessage)
        : base(logMessage)
    {
        StatusCode = statusCode;
        UserMessage = userMessage;
    }
}
