using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>
/// Roles, permissions, operators and the audit trail. Every mutating call carries
/// the acting operator so the procedure can write the audit row in its own
/// transaction - which is why the actor lives in the signature rather than in an
/// ambient context.
/// </summary>
public interface IAdminRbacProvider
{
    /// <summary>The permission names granted to one operator, resolved from their role right now.</summary>
    Task<List<string>> GetPermissionsAsync(Guid adminUserId, CancellationToken cancellationToken = default);

    Task<List<AdminRoleModel>> GetRolesAsync(CancellationToken cancellationToken = default);

    /// <summary>One role's permissions, or null when no such role exists.</summary>
    Task<AdminRolePermissionSetModel?> GetRolePermissionsAsync(string roleName, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> CreateRoleAsync(
        string name,
        string? description,
        AdminActorModel actor,
        CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteRoleAsync(string roleName, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> SetRolePermissionAsync(
        string roleName,
        string permission,
        bool granted,
        AdminActorModel actor,
        CancellationToken cancellationToken = default);

    Task<List<AdminOperatorModel>> GetOperatorsAsync(bool includeInactive, CancellationToken cancellationToken = default);

    /// <summary>
    /// Creates a brand-new operator account. Only ever inserts - an existing
    /// username comes back as <see cref="AdminWriteOutcome.Conflict"/>, never a
    /// silent credential rotation. <paramref name="roleName"/> is optional; leaving
    /// it null creates an operator with no role (deny-all until assigned one).
    /// </summary>
    Task<AdminMutationResultModel> CreateOperatorAsync(
        string username,
        byte[] passwordHash,
        byte[] passwordSalt,
        byte[] totpSecretCipher,
        string email,
        string? roleName,
        AdminActorModel actor,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Marks an operator's email confirmed. <paramref name="email"/> is re-checked
    /// against the row rather than trusted, so a link from before the address
    /// changed can never confirm the new one. Idempotent: confirming an
    /// already-confirmed address is a no-op success, not a conflict.
    /// </summary>
    Task<AdminMutationResultModel> ConfirmOperatorEmailAsync(Guid adminUserId, string email, string? clientIp, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> SetOperatorRoleAsync(string username, string roleName, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> SetOperatorActiveAsync(string username, bool isActive, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<List<AdminAuditEntryModel>> GetRecentAuditAsync(int limit, CancellationToken cancellationToken = default);
}
