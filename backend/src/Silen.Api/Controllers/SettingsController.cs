using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>User preferences (units, appearance, reminders) - open to any authenticated tier, guests included.</summary>
[ApiController]
[Route("api/settings")]
[Authorize]
public sealed class SettingsController(ISettingsService settingsService, ILogger<SettingsController> logger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken cancellationToken)
    {
        var result = await settingsService.GetAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPut]
    public async Task<IActionResult> Update([FromBody] UpdateUserSettingsRequest request, CancellationToken cancellationToken)
    {
        var result = await settingsService.UpdateAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }
}
