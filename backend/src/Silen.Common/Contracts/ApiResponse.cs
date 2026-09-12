namespace Silen.Common.Contracts;

/// <summary>
/// The single response envelope every controller action returns. Shape never
/// changes between success and failure - only Success/Data/Message do.
/// </summary>
public sealed class ApiResponse<T>
{
    public bool Success { get; init; }

    public T? Data { get; init; }

    /// <summary>User-safe message. Null on success unless the caller wants to surface one.</summary>
    public string? Message { get; init; }

    public static ApiResponse<T> Ok(T? data, string? message = null) => new()
    {
        Success = true,
        Data = data,
        Message = message
    };

    public static ApiResponse<T> Fail(string message) => new()
    {
        Success = false,
        Data = default,
        Message = message
    };
}

/// <summary>Non-generic form for endpoints that return no payload.</summary>
public sealed class ApiResponse
{
    public bool Success { get; init; }

    public string? Message { get; init; }

    public static ApiResponse Ok(string? message = null) => new() { Success = true, Message = message };

    public static ApiResponse Fail(string message) => new() { Success = false, Message = message };
}
