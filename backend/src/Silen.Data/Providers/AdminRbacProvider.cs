using Microsoft.Data.SqlClient;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

/// <inheritdoc cref="IAdminRbacProvider"/>
public sealed class AdminRbacProvider(ISqlExecutor sqlExecutor) : IAdminRbacProvider
{
    public Task<List<string>> GetPermissionsAsync(Guid adminUserId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_GetPermissions",
            [SqlParameterBuilder.Create("@AdminUserId", adminUserId)],
            reader => SqlResultSetReader.ReadListAsync(reader, row => row.GetStringValue("Permission"), cancellationToken),
            cancellationToken);

    public Task<List<AdminRoleModel>> GetRolesAsync(CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Roles_GetAll",
            [],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapRole, cancellationToken),
            cancellationToken);

    /// <summary>
    /// The procedure returns one row per permission and a single NULL row for a role
    /// that has none, which is what makes "unknown role" (no rows) distinguishable
    /// from "role with an empty grant list" without a second round trip.
    /// </summary>
    public Task<AdminRolePermissionSetModel?> GetRolePermissionsAsync(string roleName, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_RolePermissions_GetForRole",
            [SqlParameterBuilder.Create("@RoleName", roleName)],
            async reader =>
            {
                AdminRolePermissionSetModel? set = null;

                while (await reader.ReadAsync(cancellationToken))
                {
                    set ??= new AdminRolePermissionSetModel
                    {
                        RoleName = reader.GetStringValue("RoleName"),
                        IsSystemRole = reader.GetBoolValue("IsSystemRole")
                    };

                    var permission = reader.GetNullableString("Permission");
                    if (!string.IsNullOrWhiteSpace(permission))
                    {
                        set.Permissions.Add(permission);
                    }
                }

                return set;
            },
            cancellationToken);

    public Task<AdminMutationResultModel> CreateRoleAsync(
        string name,
        string? description,
        AdminActorModel actor,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Role_Create",
            [
                SqlParameterBuilder.Create("@Name", name),
                SqlParameterBuilder.Create("@Description", description),
                SqlParameterBuilder.Create("@ActorAdminUserId", actor.AdminUserId),
                SqlParameterBuilder.Create("@ActorUsername", actor.Username),
                SqlParameterBuilder.Create("@ActorIp", actor.Ip)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteRoleAsync(string roleName, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Role_Delete",
            [
                SqlParameterBuilder.Create("@Name", roleName),
                SqlParameterBuilder.Create("@ActorAdminUserId", actor.AdminUserId),
                SqlParameterBuilder.Create("@ActorUsername", actor.Username),
                SqlParameterBuilder.Create("@ActorIp", actor.Ip)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> SetRolePermissionAsync(
        string roleName,
        string permission,
        bool granted,
        AdminActorModel actor,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_RolePermission_Set",
            [
                SqlParameterBuilder.Create("@RoleName", roleName),
                SqlParameterBuilder.Create("@Permission", permission),
                SqlParameterBuilder.Create("@Granted", granted),
                SqlParameterBuilder.Create("@ActorAdminUserId", actor.AdminUserId),
                SqlParameterBuilder.Create("@ActorUsername", actor.Username),
                SqlParameterBuilder.Create("@ActorIp", actor.Ip)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<List<AdminOperatorModel>> GetOperatorsAsync(bool includeInactive, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Operators_GetAll",
            [SqlParameterBuilder.Create("@IncludeInactive", includeInactive)],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapOperator, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> CreateOperatorAsync(
        string username,
        byte[] passwordHash,
        byte[] passwordSalt,
        byte[] totpSecretCipher,
        string email,
        string? roleName,
        AdminActorModel actor,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Operator_Create",
            [
                SqlParameterBuilder.Create("@Username", username),
                SqlParameterBuilder.Create("@PasswordHash", passwordHash),
                SqlParameterBuilder.Create("@PasswordSalt", passwordSalt),
                SqlParameterBuilder.Create("@TotpSecretCipher", totpSecretCipher),
                SqlParameterBuilder.Create("@Email", email),
                SqlParameterBuilder.Create("@RoleName", roleName),
                SqlParameterBuilder.Create("@ActorAdminUserId", actor.AdminUserId),
                SqlParameterBuilder.Create("@ActorUsername", actor.Username),
                SqlParameterBuilder.Create("@ActorIp", actor.Ip)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> ConfirmOperatorEmailAsync(Guid adminUserId, string email, string? clientIp, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Operator_ConfirmEmail",
            [
                SqlParameterBuilder.Create("@AdminUserId", adminUserId),
                SqlParameterBuilder.Create("@Email", email),
                SqlParameterBuilder.Create("@ActorIp", clientIp)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> SetOperatorRoleAsync(string username, string roleName, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Operator_SetRole",
            [
                SqlParameterBuilder.Create("@Username", username),
                SqlParameterBuilder.Create("@RoleName", roleName),
                SqlParameterBuilder.Create("@ActorAdminUserId", actor.AdminUserId),
                SqlParameterBuilder.Create("@ActorUsername", actor.Username),
                SqlParameterBuilder.Create("@ActorIp", actor.Ip)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> SetOperatorActiveAsync(string username, bool isActive, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Operator_SetActive",
            [
                SqlParameterBuilder.Create("@Username", username),
                SqlParameterBuilder.Create("@IsActive", isActive),
                SqlParameterBuilder.Create("@ActorAdminUserId", actor.AdminUserId),
                SqlParameterBuilder.Create("@ActorUsername", actor.Username),
                SqlParameterBuilder.Create("@ActorIp", actor.Ip)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<List<AdminAuditEntryModel>> GetRecentAuditAsync(int limit, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_Audit_GetRecent",
            [SqlParameterBuilder.Create("@Limit", limit)],
            reader => SqlResultSetReader.ReadListAsync(reader, AdminContentRowMapper.MapAuditEntry, cancellationToken),
            cancellationToken);
}
