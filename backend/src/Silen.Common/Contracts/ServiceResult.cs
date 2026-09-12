namespace Silen.Common.Contracts;

/// <summary>
/// Outcome of a service-layer call. Carries the HTTP status the API layer
/// should use, a safe user-facing message and a detailed log message,
/// without ever forcing the service layer to throw for expected outcomes.
/// Build instances via <see cref="Silen.Common.Helpers.ServiceExecutor"/>
/// rather than constructing them by hand in a service implementation.
/// </summary>
public sealed class ServiceResult<T>
{
    public bool IsSuccess { get; init; }

    public T? Data { get; init; }

    public int StatusCode { get; init; }

    public string? UserMessage { get; init; }

    public string? LogMessage { get; init; }

    public static ServiceResult<T> Success(T data, int statusCode = 200) => new()
    {
        IsSuccess = true,
        Data = data,
        StatusCode = statusCode
    };

    public static ServiceResult<T> Failure(int statusCode, string userMessage, string logMessage) => new()
    {
        IsSuccess = false,
        StatusCode = statusCode,
        UserMessage = userMessage,
        LogMessage = logMessage
    };
}
