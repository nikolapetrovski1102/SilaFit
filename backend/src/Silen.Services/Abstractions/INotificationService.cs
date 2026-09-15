using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

/// <summary>
/// Client-facing side of notifications: registering/refreshing a device push
/// token (and the timezone + opt-in that travel with it), and recording that
/// the user used the app so the backoff logic knows they are still here.
/// </summary>
public interface INotificationService
{
    Task<ServiceResult<bool>> RegisterDeviceTokenAsync(
        Guid userId, RegisterDeviceTokenRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<bool>> DeactivateDeviceTokenAsync(
        Guid userId, DeactivateDeviceTokenRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<bool>> RecordInteractionAsync(
        Guid userId, RecordNotificationInteractionRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<bool>> RecordWorkoutHeartbeatAsync(
        Guid userId, Guid? workoutSessionId, CancellationToken cancellationToken = default);
}
