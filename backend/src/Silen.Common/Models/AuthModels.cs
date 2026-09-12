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
