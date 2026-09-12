using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>Onboarding-collected profile data (gender/age/height/weight/goal) - open to any authenticated tier, guests included.</summary>
[ApiController]
[Route("api/profile")]
[Authorize]
public sealed class UserProfileController(IUserProfileService userProfileService, ILogger<UserProfileController> logger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken cancellationToken)
    {
        var result = await userProfileService.GetAsync(User.GetUserId(), cancellationToken);
        return result.ToActionResult(logger);
    }

    [HttpPut]
    public async Task<IActionResult> Upsert([FromBody] UpsertUserProfileRequest request, CancellationToken cancellationToken)
    {
        var result = await userProfileService.UpsertAsync(User.GetUserId(), request, cancellationToken);
        return result.ToActionResult(logger);
    }
}
