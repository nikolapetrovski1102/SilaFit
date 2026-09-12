namespace Silen.Common.Enums;

/// <summary>
/// Identity providers a user can be authenticated or linked with. Device is
/// the anonymous/guest entry point; the other three link a real identity to
/// the user's existing UserId (preserving history).
/// </summary>
public enum AuthProvider
{
    Device = 0,
    Email = 1,
    Google = 2,
    Apple = 3
}
