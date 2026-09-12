using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;

namespace Silen.Common.Helpers;

/// <summary>
/// Outside helper for reading the claims <see cref="JwtTokenFactory"/> issues,
/// so controllers never need a private method to pull the user id off the
/// current principal.
/// </summary>
public static class ClaimsPrincipalExtensions
{
    /// <summary>The authenticated user's id. Only call this on a principal known to be authenticated (e.g. behind [Authorize]).</summary>
    public static Guid GetUserId(this ClaimsPrincipal principal) =>
        Guid.Parse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub)!);

    /// <summary>The current user's id if a valid JWT was presented, otherwise null - for endpoints that accept both anonymous and Guest-linking calls.</summary>
    public static Guid? GetUserIdOrNull(this ClaimsPrincipal principal) =>
        principal.Identity?.IsAuthenticated == true ? principal.GetUserId() : null;
}
