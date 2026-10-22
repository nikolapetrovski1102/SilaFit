using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Options;
using Silen.Common.Contracts;
using Silen.Common.Helpers;
using Silen.Common.Options;

namespace Silen.Api.Filters;

/// <summary>HTTP Basic auth for the partner website's server-to-server calls. Runs before
/// model binding, so an unauthenticated caller never gets as far as the payload.</summary>
public sealed class PartnerBasicAuthFilter(IOptions<PartnerOptions> partnerOptions, ILogger<PartnerBasicAuthFilter> logger) : IAuthorizationFilter
{
    public void OnAuthorization(AuthorizationFilterContext context)
    {
        var httpContext = context.HttpContext;
        if (PartnerBasicAuth.IsAuthorized(httpContext.Request.Headers.Authorization, partnerOptions.Value))
        {
            return;
        }

        logger.LogWarning(
            "Partner call to {Path} from {RemoteIp} rejected: missing or wrong Basic credentials.",
            httpContext.Request.Path, httpContext.Connection.RemoteIpAddress);

        httpContext.Response.Headers.WWWAuthenticate = PartnerBasicAuth.Challenge;
        context.Result = new ObjectResult(ApiResponse.Fail("Invalid partner credentials."))
        {
            StatusCode = StatusCodes.Status401Unauthorized
        };
    }
}
