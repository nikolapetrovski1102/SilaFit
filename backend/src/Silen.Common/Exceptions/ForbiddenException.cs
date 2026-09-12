namespace Silen.Common.Exceptions;

/// <summary>
/// 403: the caller is a valid, signed-in operator, but their role does not carry
/// the permission this endpoint needs.
///
/// Distinct from <see cref="UnauthorizedAppException"/> on purpose - the console
/// treats them differently. A 401 means "your session is gone, sign in again"; a
/// 403 means "you are signed in, this just isn't yours to do", and re-authenticating
/// would be pointless.
/// </summary>
public sealed class ForbiddenException : AppException
{
    public ForbiddenException(string logMessage, string? userMessage = null)
        : base(403, userMessage ?? "Your role does not allow that.", logMessage)
    {
    }
}
