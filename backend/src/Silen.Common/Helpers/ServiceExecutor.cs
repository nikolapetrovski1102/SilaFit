using Silen.Common.Contracts;
using Silen.Common.Exceptions;

namespace Silen.Common.Helpers;

/// <summary>
/// Runs service-layer logic and converts the outcome into a
/// <see cref="ServiceResult{T}"/>. Implementation classes call this instead
/// of wrapping their own try/catch in a private method, so every
/// implementation gets the exact same error handling / fallback-message
/// behaviour from one shared place.
/// </summary>
public static class ServiceExecutor
{
    private const string GlobalFallbackMessage = "Something went wrong";

    public static async Task<ServiceResult<T>> RunAsync<T>(Func<Task<T>> action)
    {
        try
        {
            var data = await action().ConfigureAwait(false);
            return ServiceResult<T>.Success(data);
        }
        catch (AppException ex)
        {
            return ServiceResult<T>.Failure(ex.StatusCode, ex.UserMessage, ex.Message);
        }
        catch (Exception ex)
        {
            return ServiceResult<T>.Failure(500, GlobalFallbackMessage, ex.ToString());
        }
    }

    public static async Task<ServiceResult<bool>> RunAsync(Func<Task> action)
    {
        try
        {
            await action().ConfigureAwait(false);
            return ServiceResult<bool>.Success(true);
        }
        catch (AppException ex)
        {
            return ServiceResult<bool>.Failure(ex.StatusCode, ex.UserMessage, ex.Message);
        }
        catch (Exception ex)
        {
            return ServiceResult<bool>.Failure(500, GlobalFallbackMessage, ex.ToString());
        }
    }
}
