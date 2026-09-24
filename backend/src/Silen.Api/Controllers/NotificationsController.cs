using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>
/// Client side of the notification pipeline: device-token registration (with
/// the timezone + opt-in captured during onboarding) and the "user is here"
/// interaction signal the backoff logic depends on. Open to any authenticated
/// tier, guests included - reminders are useful before an account is linked.
/// </summary>
[ApiController]
[Route("api/notifications")]
[Authorize]
public sealed class NotificationsController(INotificationService notificationService, ILogger<NotificationsController> logger) : ControllerBase
{
    [HttpPost("device-token")]
    public async Task<IActionResult> RegisterDeviceToken(
        [FromBody] RegisterDeviceTokenRequest request, CancellationToken cancellationToken)
    {
        var result = await notificationService.RegisterDeviceTokenAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpDelete("device-token")]
    public async Task<IActionResult> DeactivateDeviceToken(
        [FromBody] DeactivateDeviceTokenRequest request, CancellationToken cancellationToken)
    {
        var result = await notificationService.DeactivateDeviceTokenAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("interaction")]
    public async Task<IActionResult> RecordInteraction(
        [FromBody] RecordNotificationInteractionRequest request, CancellationToken cancellationToken)
    {
        var result = await notificationService.RecordInteractionAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPost("workout-heartbeat")]
    public async Task<IActionResult> RecordWorkoutHeartbeat(
        [FromBody] WorkoutHeartbeatRequest? request, CancellationToken cancellationToken)
    {
        var result = await notificationService.RecordWorkoutHeartbeatAsync(
            User.GetUserId(), request?.WorkoutSessionId, request?.HasCompletedSets ?? false, cancellationToken);
        return result.ToActionResult(logger);
    }
}
