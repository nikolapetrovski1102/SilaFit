using Silen.Common.Enums;

namespace Silen.Common.Models;

/// <summary>
/// Maps 1:1 to the columns every Auth stored procedure that returns a user
/// row selects. PasswordHash/Salt are only populated by the one procedure
/// that needs them (GetUserByEmail) - every other caller ignores them.
/// </summary>
public sealed class UserAccountModel
{
    public Guid UserId { get; set; }
    public string? DeviceId { get; set; }
    public string? DisplayName { get; set; }
    public string? Email { get; set; }
    public byte[]? PasswordHash { get; set; }
    public byte[]? PasswordSalt { get; set; }
    public AccountTier AccountTier { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public DateTime? LastLoginAtUtc { get; set; }
    public bool IsActive { get; set; }
}

/// <summary>Verified claims extracted from a Google/Apple identity token.</summary>
public sealed class ExternalIdentityPayload
{
    public string Subject { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string? DisplayName { get; set; }
}

/// <summary>
/// An email/password registration awaiting its emailed code - everything
/// usp_Auth_RegisterEmailUser will need, held outside dbo.Users until the
/// code is confirmed. See usp_Auth_UpsertPendingEmailVerification.
/// </summary>
public sealed class PendingEmailVerificationModel
{
    public Guid PendingId { get; set; }
    public Guid? ExistingUserId { get; set; }
    public string Email { get; set; } = string.Empty;
    public byte[] PasswordHash { get; set; } = [];
    public byte[] PasswordSalt { get; set; } = [];
    public string? DisplayName { get; set; }
    public byte[] CodeHash { get; set; } = [];
    public byte[] CodeSalt { get; set; } = [];
    public int AttemptCount { get; set; }
    public DateTime ExpiresAtUtc { get; set; }
    public DateTime LastSentAtUtc { get; set; }
}
