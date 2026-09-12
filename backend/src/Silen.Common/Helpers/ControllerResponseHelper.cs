using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Silen.Common.Contracts;

namespace Silen.Common.Helpers;

/// <summary>
/// Maps a <see cref="ServiceResult{T}"/> straight into the
/// <see cref="ApiResponse{T}"/>-wrapped <see cref="IActionResult"/> every
/// controller action returns, logging the detailed message on failure.
/// This is the "outside helper" controllers call instead of having any
/// private mapping/logging logic of their own.
/// </summary>
public static class ControllerResponseHelper
{
    public static IActionResult ToActionResult<T>(this ServiceResult<T> result, ILogger logger)
    {
        if (result.IsSuccess)
        {
            return new ObjectResult(ApiResponse<T>.Ok(result.Data)) { StatusCode = result.StatusCode };
        }

        logger.LogError("Request failed with status {StatusCode}: {LogMessage}", result.StatusCode, result.LogMessage);

        return new ObjectResult(ApiResponse<T>.Fail(result.UserMessage ?? "Something went wrong"))
        {
            StatusCode = result.StatusCode
        };
    }
}
