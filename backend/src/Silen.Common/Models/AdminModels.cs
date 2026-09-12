namespace Silen.Common.Models;

/// <summary>
/// Maps 1:1 to the columns every Admin stored procedure selects for an operator
/// account. PasswordSalt/TotpSecretCipher are only meaningful to the login path
/// and the provisioning tool - everything else ignores them.
/// </summary>
public sealed class AdminAccountModel
{
    public Guid AdminUserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public byte[] PasswordHash { get; set; } = [];
    public byte[] PasswordSalt { get; set; } = [];
    public byte[] TotpSecretCipher { get; set; } = [];
    public int FailedAttemptCount { get; set; }
    public DateTime? LockedUntilUtc { get; set; }
    public DateTime? LastLoginAtUtc { get; set; }
    public DateTime PasswordChangedAtUtc { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public bool IsActive { get; set; }

    /// <summary>
    /// Which role this operator holds. Null is a valid state and means "no role":
    /// authorization fails closed, so a half-provisioned account can sign in and
    /// still be allowed to do nothing.
    /// </summary>
    public Guid? RoleId { get; set; }

    public string? RoleName { get; set; }
}

/// <summary>Result of recording a failed sign-in - what the caller needs to say "try again in N minutes".</summary>
public sealed class AdminLockoutStateModel
{
    public int FailedAttemptCount { get; set; }
    public DateTime? LockedUntilUtc { get; set; }
}

/// <summary>An authenticated console session, joined to the operator it belongs to.</summary>
public sealed class AdminSessionModel
{
    public Guid AdminSessionId { get; set; }
    public Guid AdminUserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public DateTime ExpiresAtUtc { get; set; }
    public DateTime AbsoluteExpiresAtUtc { get; set; }
    public DateTime LastSeenAtUtc { get; set; }
}

/// <summary>
/// Verified contents of a password-step challenge token: who passed the password
/// check, and nothing else. The second factor is still outstanding.
/// </summary>
public sealed class AdminChallengeModel
{
    public Guid AdminUserId { get; set; }
    public string Username { get; set; } = string.Empty;
}
