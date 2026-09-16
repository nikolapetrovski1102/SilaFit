namespace Silen.Common.Dtos;

/// <summary>
/// One entry of the permission catalog the role editor renders. Sent from the API
/// so the console never keeps its own copy of the permission list and cannot drift
/// from what the database can actually grant.
/// </summary>
public sealed class AdminPermissionDto
{
    public string Permission { get; set; } = string.Empty;
    public string Group { get; set; } = string.Empty;
    public string Label { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
}

/// <summary>A role with its grant list: what the roles screen shows and edits.</summary>
public sealed class AdminRoleDto
{
    public Guid RoleId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public bool IsSystemRole { get; set; }
    public int OperatorCount { get; set; }
    public List<string> Permissions { get; set; } = [];
}

public sealed class AdminRoleCreateRequest
{
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
}

/// <summary>Grant or revoke one permission on one custom role.</summary>
public sealed class AdminRolePermissionRequest
{
    public string RoleName { get; set; } = string.Empty;
    public string Permission { get; set; } = string.Empty;
    public bool Granted { get; set; } = true;
}

public sealed class AdminOperatorDto
{
    public Guid AdminUserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string? RoleName { get; set; }
    public bool IsActive { get; set; }
    public int ActiveSessionCount { get; set; }
    public DateTime? LastLoginAtUtc { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public string? Email { get; set; }

    /// <summary>True once the operator has clicked the link in their confirmation email.</summary>
    public bool EmailConfirmed { get; set; }
}

/// <summary>Adds a brand-new operator from the dashboard. Only ever creates - never rotates an existing account.</summary>
public sealed class AdminOperatorCreateRequest
{
    public string Username { get; set; } = string.Empty;

    /// <summary>Set by whoever is creating the account and shared with the new operator out of band, like a handed-over temporary password.</summary>
    public string Password { get; set; } = string.Empty;

    /// <summary>
    /// Required so every operator has a proven way to receive the "send email code
    /// instead" second factor and account-recovery notices. A confirmation email is
    /// sent here immediately after creation; the address does nothing until its link
    /// is clicked (see AdminRbacService.ConfirmOperatorEmailAsync).
    /// </summary>
    public string Email { get; set; } = string.Empty;

    /// <summary>Optional - an operator can be created with no role (deny-all) and assigned one later.</summary>
    public string? RoleName { get; set; }
}

/// <summary>The token from an operator's confirmation-email link.</summary>
public sealed class AdminConfirmOperatorEmailRequest
{
    public string Token { get; set; } = string.Empty;
}

/// <summary>
/// Shown exactly once, immediately after an operator is created - like the CLI
/// provisioning tool's console output, but returned over HTTP instead of printed.
/// <see cref="TotpSecret"/>/<see cref="OtpAuthUri"/> are never retrievable again:
/// only their encrypted form is stored, so losing this response means re-enrolling.
/// </summary>
public sealed class AdminOperatorCreatedDto
{
    public Guid AdminUserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string? RoleName { get; set; }
    public string TotpSecret { get; set; } = string.Empty;
    public string OtpAuthUri { get; set; } = string.Empty;
}

public sealed class AdminOperatorRoleRequest
{
    public string Username { get; set; } = string.Empty;
    public string RoleName { get; set; } = string.Empty;
}

public sealed class AdminOperatorActiveRequest
{
    public string Username { get; set; } = string.Empty;
    public bool IsActive { get; set; }
}

public sealed class AdminAuditEntryDto
{
    public Guid AuditId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Action { get; set; } = string.Empty;
    public string EntityType { get; set; } = string.Empty;
    public string? EntityId { get; set; }
    public string? Summary { get; set; }
    public string? CreatedFromIp { get; set; }
    public DateTime CreatedAtUtc { get; set; }
}

/// <summary>
/// Result of a successful write. Message is written for a toast, not a log line -
/// the audit trail is the record of what happened, this is just the confirmation.
/// </summary>
public sealed class AdminWriteResultDto
{
    public Guid? Id { get; set; }
    public string Message { get; set; } = string.Empty;
}
