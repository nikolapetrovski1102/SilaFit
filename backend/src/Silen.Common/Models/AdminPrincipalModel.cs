namespace Silen.Common.Models;

/// <summary>
/// Everything an authenticated console request needs to know about its caller:
/// who they are, what role they hold, and what that role currently allows.
///
/// Assembled per request from the session cookie (session -> operator -> role ->
/// permissions), which is what makes a privilege change take effect on the next
/// click instead of whenever a cookie happens to expire.
/// </summary>
public sealed class AdminPrincipalModel
{
    public Guid AdminUserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string? RoleName { get; set; }
    public List<string> Permissions { get; set; } = [];
    public DateTime ExpiresAtUtc { get; set; }
    public DateTime AbsoluteExpiresAtUtc { get; set; }

    public bool Has(string permission) => Permissions.Contains(permission);
}
