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

    Task<AdminMutationResultModel> SetOperatorRoleAsync(string username, string roleName, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> SetOperatorActiveAsync(string username, bool isActive, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<List<AdminAuditEntryModel>> GetRecentAuditAsync(int limit, CancellationToken cancellationToken = default);
}
