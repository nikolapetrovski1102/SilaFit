using Silen.Common.Exceptions;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;

namespace Silen.Services.Helpers;

/// <summary>
/// The lockout half of console sign-in, kept outside <c>AdminAuthService</c> so the
/// service class stays free of private methods (same reason
/// <see cref="ProgressInsightGenerator"/> exists).
///
/// Both factors share one counter on purpose: a wrong authenticator code is as much
/// a failed sign-in as a wrong password, and counting only the password would leave
/// the 6-digit space open to brute force for anyone who has the password.
/// </summary>
public static class AdminSignInThrottle
{
    /// <summary>Refuses a sign-in while the account is inside its lockout window.</summary>
    public static void ThrowIfLocked(AdminAccountModel account, AdminAuthOptions options)
    {
        if (account.LockedUntilUtc is not null && account.LockedUntilUtc > DateTime.UtcNow)
        {
            throw new TooManyRequestsException(
                $"Admin '{account.Username}' is locked until {account.LockedUntilUtc:O}.",
                LockedMessage(account.LockedUntilUtc.Value));
        }
    }

    /// <summary>
    /// Counts one failed attempt and, when that attempt trips the threshold, throws
    /// 429 instead of letting the caller report it as a plain bad credential.
    /// </summary>
    public static async Task RecordFailureAsync(
        IAdminProvider adminProvider,
        AdminAccountModel account,
        AdminAuthOptions options,
        CancellationToken cancellationToken)
    {
        var state = await adminProvider.RecordFailedLoginAsync(
            account.AdminUserId, options.LockoutThreshold, options.LockoutMinutes, cancellationToken);

        if (state?.LockedUntilUtc is not null && state.LockedUntilUtc > DateTime.UtcNow)
        {
            throw new TooManyRequestsException(
                $"Admin '{account.Username}' locked after {state.FailedAttemptCount} failed attempts.",
                LockedMessage(state.LockedUntilUtc.Value));
        }
    }

    private static string LockedMessage(DateTime lockedUntilUtc)
    {
        var minutesRemaining = Math.Max(1, (int)Math.Ceiling((lockedUntilUtc - DateTime.UtcNow).TotalMinutes));
        return $"Too many failed attempts. This account is locked for another {minutesRemaining} minute(s).";
    }
}
