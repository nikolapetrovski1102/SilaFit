using Silen.Common.Helpers;
using Silen.Common.Models;

namespace Silen.Services.Helpers;

/// <summary>
/// The "send email code instead" half of the second factor, kept outside
/// AdminAuthService for the same reason as <see cref="AdminSignInThrottle"/>: the
/// service class stays free of private methods.
/// </summary>
public static class AdminEmailOtpValidator
{
    /// <summary>True when the account has an unexpired emailed code and it matches. Does not
    /// consume the code - the caller clears it on successful sign-in (usp_Admin_RecordSuccessfulLogin).</summary>
    public static bool IsValid(AdminAccountModel account, string code) =>
        account.EmailOtpCodeHash is { Length: > 0 } hash &&
        account.EmailOtpCodeSalt is { Length: > 0 } salt &&
        account.EmailOtpExpiresAtUtc is { } expiresAtUtc &&
        expiresAtUtc > DateTime.UtcNow &&
        PasswordHasher.Verify(code, hash, salt);
}
