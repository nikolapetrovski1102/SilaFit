using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;

namespace Silen.Services.Helpers;

/// <summary>
/// Turns a cookie value into a live session row, or refuses. Outside helper so
/// <c>AdminAuthService</c> needs no private method for the lookup it does on every
/// authenticated call.
///
/// The three ways a cookie can be dead - unknown token, idle/absolute expiry, or a
/// deactivated account - all surface as the same 401, because the browser's only
/// sane reaction is identical anyway: sign in again.
/// </summary>
public static class AdminSessionResolver
{
    public static async Task<AdminSessionModel> ResolveOrThrowAsync(
        IAdminProvider adminProvider,
        string? sessionToken,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(sessionToken))
        {
            throw new UnauthorizedAppException("Admin session endpoint called without a cookie.");
        }

        return await adminProvider.GetSessionAsync(AdminSessionTokenFactory.HashToken(sessionToken), cancellationToken)
            ?? throw new UnauthorizedAppException("Admin session token did not resolve to a live session (unknown, expired or inactive account).");
    }
}
