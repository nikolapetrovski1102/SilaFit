namespace Silen.Common.Dtos;

public sealed class DeviceLoginRequest
{
    public string DeviceId { get; set; } = string.Empty;
}

public sealed class EmailRegisterRequest
{
    /// <summary>When the caller already holds a Guest JWT, its UserId claim is
    /// passed here by the controller so the upgrade preserves history. Not set
    /// by the client directly.</summary>
    public Guid? ExistingUserId { get; set; }
    public string Email { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string? DisplayName { get; set; }
}

public sealed class EmailLoginRequest
{
    public string Email { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}

public sealed class GoogleLoginRequest
{
    public Guid? ExistingUserId { get; set; }
    public string IdToken { get; set; } = string.Empty;
}

public sealed class AppleLoginRequest
{
    public Guid? ExistingUserId { get; set; }
    public string IdentityToken { get; set; } = string.Empty;
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
