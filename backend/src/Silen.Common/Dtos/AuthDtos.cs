using System.ComponentModel.DataAnnotations;

namespace Silen.Common.Dtos;

public sealed class DeviceLoginRequest
{
    /// <summary>Caps length before it reaches the DB (proc parameter is NVARCHAR(200)).</summary>
    [Required]
    [StringLength(200, MinimumLength = 1)]
    public string DeviceId { get; set; } = string.Empty;
}

public sealed class EmailRegisterRequest
{
    /// <summary>When the caller already holds a Guest JWT, its UserId claim is
    /// passed here by the controller so the upgrade preserves history. Not set
    /// by the client directly.</summary>
    public Guid? ExistingUserId { get; set; }

    [Required]
    [EmailAddress]
    [StringLength(256)]
    public string Email { get; set; } = string.Empty;

    // Min 8 matches the client-side rule; the max stops PBKDF2 being used as a
    // CPU/memory amplification primitive with a multi-megabyte "password".
    [Required]
    [StringLength(200, MinimumLength = 8)]
    public string Password { get; set; } = string.Empty;

    [StringLength(100)]
    public string? DisplayName { get; set; }
}

public sealed class EmailLoginRequest
{
    [Required]
    [EmailAddress]
    [StringLength(256)]
    public string Email { get; set; } = string.Empty;

    // Cap only, no minimum: existing accounts may predate the 8-char rule.
    [Required]
    [StringLength(200)]
    public string Password { get; set; } = string.Empty;
}

public sealed class GoogleLoginRequest
{
    public Guid? ExistingUserId { get; set; }

    [Required]
    [StringLength(8192)]
    public string IdToken { get; set; } = string.Empty;
}

public sealed class AppleLoginRequest
{
    public Guid? ExistingUserId { get; set; }

    [Required]
    [StringLength(8192)]
    public string IdentityToken { get; set; } = string.Empty;

    [StringLength(100)]
    public string? DisplayName { get; set; }
}

public sealed class AuthResultDto
{
    public string Token { get; set; } = string.Empty;
    public Guid UserId { get; set; }
    public string AccountTier { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string? DisplayName { get; set; }
}

/// <summary>Returned by both register/email/start and .../resend - the client holds onto
/// <see cref="PendingId"/> and passes it back to .../verify along with the code the user typed.</summary>
public sealed class EmailVerificationStartResultDto
{
    public Guid PendingId { get; set; }
    public int ExpiresInSeconds { get; set; }
}

public sealed class EmailVerificationRequest
{
    public Guid PendingId { get; set; }

    [Required]
    [StringLength(12, MinimumLength = 1)]
    public string Code { get; set; } = string.Empty;
}

public sealed class ResendEmailVerificationRequest
{
    public Guid PendingId { get; set; }
}
