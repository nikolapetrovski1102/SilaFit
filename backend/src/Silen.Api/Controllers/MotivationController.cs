using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Silen.Common.Helpers;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>Motivational lines for the app's splash screen. Anonymous, since the splash
/// fetches them before the device/user sign-in has finished.</summary>
[ApiController]
[Route("api/motivation")]
[AllowAnonymous]
public sealed class MotivationController(IMotivationalQuoteService quoteService, ILogger<MotivationController> logger) : ControllerBase
{
    [HttpGet("quotes")]
    [ResponseCache(Duration = 600, Location = ResponseCacheLocation.Any)]
    public async Task<IActionResult> GetQuotes(CancellationToken cancellationToken) =>
        (await quoteService.GetActiveAsync(cancellationToken)).ToActionResult(logger);
}
