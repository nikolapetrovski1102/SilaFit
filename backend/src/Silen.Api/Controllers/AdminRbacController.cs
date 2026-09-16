using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Silen.Common.Dtos;
using Silen.Common.Helpers;
using Silen.Common.Options;
using Silen.Services.Abstractions;

namespace Silen.Api.Controllers;

/// <summary>
/// Role, permission, operator and audit-log management for the console - the
/// "who can do what" screens a super admin uses to add operators and shape their
/// access.
///
/// Same authentication shape as <see cref="AdminAuthController"/> and deliberately
/// not [Authorize]: the credential is the HttpOnly session cookie, not a bearer
/// token. Every action here additionally requires a specific permission on top of
/// just being signed in - <see cref="Silen.Services.Helpers.AdminPermissionGuard"/>
/// enforces that inside the service layer and throws a 403 when it's missing, so
/// there is nothing to check here beyond passing the cookie through.
/// </summary>
[ApiController]
[Route("api/admin/rbac")]
public sealed class AdminRbacController(
    IAdminRbacService rbacService,
    IOptions<AdminAuthOptions> adminAuthOptions,
    ILogger<AdminRbacController> logger) : ControllerBase
{
    private string? SessionToken => AdminSessionCookie.Read(Request, adminAuthOptions.Value);

    private string? ClientIp => HttpContext.Connection.RemoteIpAddress?.ToString();

    [HttpGet("permissions")]
    public async Task<IActionResult> GetPermissionCatalog(CancellationToken cancellationToken) =>
        (await rbacService.GetPermissionCatalogAsync(SessionToken, cancellationToken)).ToActionResult(logger);

    [HttpGet("roles")]
    public async Task<IActionResult> GetRoles(CancellationToken cancellationToken) =>
        (await rbacService.GetRolesAsync(SessionToken, cancellationToken)).ToActionResult(logger);

    [HttpGet("roles/{roleName}")]
    public async Task<IActionResult> GetRole(string roleName, CancellationToken cancellationToken) =>
        (await rbacService.GetRolePermissionsAsync(SessionToken, roleName, cancellationToken)).ToActionResult(logger);

    [HttpPost("roles")]
    public async Task<IActionResult> CreateRole([FromBody] AdminRoleCreateRequest request, CancellationToken cancellationToken) =>
        (await rbacService.CreateRoleAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpDelete("roles/{roleName}")]
    public async Task<IActionResult> DeleteRole(string roleName, CancellationToken cancellationToken) =>
        (await rbacService.DeleteRoleAsync(SessionToken, roleName, ClientIp, cancellationToken)).ToActionResult(logger);

    /// <summary>Grants or revokes one permission on one custom role - the read/write toggle behind a role's checkboxes.</summary>
    [HttpPut("roles/permission")]
    public async Task<IActionResult> SetRolePermission([FromBody] AdminRolePermissionRequest request, CancellationToken cancellationToken) =>
        (await rbacService.SetRolePermissionAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpGet("operators")]
    public async Task<IActionResult> GetOperators([FromQuery] bool includeInactive, CancellationToken cancellationToken) =>
        (await rbacService.GetOperatorsAsync(SessionToken, includeInactive, cancellationToken)).ToActionResult(logger);

    /// <summary>Adds a new admin operator. The response carries their TOTP secret once - it is never retrievable again.</summary>
    [HttpPost("operators")]
    public async Task<IActionResult> CreateOperator([FromBody] AdminOperatorCreateRequest request, CancellationToken cancellationToken) =>
        (await rbacService.CreateOperatorAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    /// <summary>
    /// Confirms the email a new operator was created with, from the link in their
    /// confirmation email. Deliberately reads no session cookie: the recipient may
    /// not have signed in yet, so the token in the body is the only credential.
    /// </summary>
    [HttpPost("operators/confirm-email")]
    public async Task<IActionResult> ConfirmOperatorEmail([FromBody] AdminConfirmOperatorEmailRequest request, CancellationToken cancellationToken) =>
        (await rbacService.ConfirmOperatorEmailAsync(request.Token, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpPut("operators/role")]
    public async Task<IActionResult> SetOperatorRole([FromBody] AdminOperatorRoleRequest request, CancellationToken cancellationToken) =>
        (await rbacService.SetOperatorRoleAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpPut("operators/active")]
    public async Task<IActionResult> SetOperatorActive([FromBody] AdminOperatorActiveRequest request, CancellationToken cancellationToken) =>
        (await rbacService.SetOperatorActiveAsync(SessionToken, request, ClientIp, cancellationToken)).ToActionResult(logger);

    [HttpGet("audit")]
    public async Task<IActionResult> GetRecentAudit([FromQuery] int limit, CancellationToken cancellationToken) =>
        (await rbacService.GetRecentAuditAsync(SessionToken, limit == 0 ? 50 : limit, cancellationToken)).ToActionResult(logger);
}
