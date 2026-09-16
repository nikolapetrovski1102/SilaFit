using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

/// <summary>
/// Role, permission, operator and audit-log management for the console -
/// everything behind the "Roles" / "Operators" screens. Deliberately its own
/// interface rather than folded into the (unimplemented) content-CRUD
/// <c>IAdminConsoleService</c>: this is the access-control surface, and it has
/// nothing to do with plans, splits or exercises.
///
/// Every method takes the raw session cookie value, the same way
/// <see cref="IAdminAuthService"/> does, and resolves both "who is this" and
/// "may they do this" from it via <c>AdminPermissionGuard</c> - so a controller
/// action is always a one-liner that trusts the cookie, never a bearer token.
/// </summary>
public interface IAdminRbacService
{
    /// <summary>The full set of permission names the database can grant, for the role editor. Requires roles.manage.</summary>
    Task<ServiceResult<List<AdminPermissionDto>>> GetPermissionCatalogAsync(string? sessionToken, CancellationToken cancellationToken = default);

    /// <summary>Every role and how many operators/permissions it carries. Requires roles.manage.</summary>
    Task<ServiceResult<List<AdminRoleDto>>> GetRolesAsync(string? sessionToken, CancellationToken cancellationToken = default);

    /// <summary>One role's full permission grant list. Requires roles.manage.</summary>
    Task<ServiceResult<AdminRoleDto>> GetRolePermissionsAsync(string? sessionToken, string roleName, CancellationToken cancellationToken = default);

    /// <summary>Creates a new custom role with no permissions granted yet. Requires roles.manage.</summary>
    Task<ServiceResult<AdminWriteResultDto>> CreateRoleAsync(string? sessionToken, AdminRoleCreateRequest request, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Deletes a custom role. Refused for system roles or roles still assigned to an operator. Requires roles.manage.</summary>
    Task<ServiceResult<AdminWriteResultDto>> DeleteRoleAsync(string? sessionToken, string roleName, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Grants or revokes one permission on one custom role. Requires roles.manage.</summary>
    Task<ServiceResult<AdminWriteResultDto>> SetRolePermissionAsync(string? sessionToken, AdminRolePermissionRequest request, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Every console operator. Requires operators.manage.</summary>
    Task<ServiceResult<List<AdminOperatorDto>>> GetOperatorsAsync(string? sessionToken, bool includeInactive, CancellationToken cancellationToken = default);

    /// <summary>
    /// Creates a new operator account with its own password, TOTP secret and
    /// email, optionally assigned a role immediately. The secret/otpauth URI in
    /// the response are shown exactly once - the server keeps only their
    /// encrypted form, so this response is the operator's one chance to enroll
    /// their authenticator app. Also sends a confirmation email to the address on
    /// file; it does nothing (see <see cref="ConfirmOperatorEmailAsync"/>) until
    /// its link is clicked. Requires operators.manage.
    /// </summary>
    Task<ServiceResult<AdminOperatorCreatedDto>> CreateOperatorAsync(string? sessionToken, AdminOperatorCreateRequest request, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>
    /// Confirms the email a new operator was created with, from the link in their
    /// confirmation email. Unauthenticated by design - the signed, time-limited
    /// token is the proof, not a session cookie.
    /// </summary>
    Task<ServiceResult<AdminWriteResultDto>> ConfirmOperatorEmailAsync(string token, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Moves an operator to a different role. Drops that operator's live sessions. Requires operators.manage.</summary>
    Task<ServiceResult<AdminWriteResultDto>> SetOperatorRoleAsync(string? sessionToken, AdminOperatorRoleRequest request, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>Activates or deactivates an operator. Deactivating drops their live sessions. Requires operators.manage.</summary>
    Task<ServiceResult<AdminWriteResultDto>> SetOperatorActiveAsync(string? sessionToken, AdminOperatorActiveRequest request, string? clientIp, CancellationToken cancellationToken = default);

    /// <summary>The most recent audit trail entries, newest first. Requires audit.read.</summary>
    Task<ServiceResult<List<AdminAuditEntryDto>>> GetRecentAuditAsync(string? sessionToken, int limit, CancellationToken cancellationToken = default);
}
