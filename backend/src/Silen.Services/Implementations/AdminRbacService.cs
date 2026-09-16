using Microsoft.Extensions.Options;
using Silen.Common.Authorization;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IAdminRbacService"/>
public sealed class AdminRbacService(
    IAdminProvider adminProvider,
    IAdminRbacProvider adminRbacProvider,
    IEmailSender emailSender,
    IOptions<AdminAuthOptions> adminAuthOptions,
    IOptions<JwtOptions> jwtOptions,
    IOptions<EncryptionOptions> encryptionOptions) : IAdminRbacService
{
    /// <summary>Same floor the CLI provisioning tool enforces - one account creation path, one rule.</summary>
    private const int MinimumPasswordLength = 12;

    public Task<ServiceResult<List<AdminPermissionDto>>> GetPermissionCatalogAsync(string? sessionToken, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await RequireAsync(sessionToken, AdminPermissions.RolesManage, null, cancellationToken);

            return AdminPermissions.Catalog
                .Select(descriptor => new AdminPermissionDto
                {
                    Permission = descriptor.Permission,
                    Group = descriptor.Group,
                    Label = descriptor.Label,
                    Description = descriptor.Description
                })
                .ToList();
        });

    public Task<ServiceResult<List<AdminRoleDto>>> GetRolesAsync(string? sessionToken, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await RequireAsync(sessionToken, AdminPermissions.RolesManage, null, cancellationToken);

            var roles = await adminRbacProvider.GetRolesAsync(cancellationToken);
            var result = new List<AdminRoleDto>(roles.Count);

            // One extra round trip per role for its full grant list - the role count
            // is small (a handful of system roles plus whatever custom ones exist) and
            // this screen loads rarely, so N+1 here beats a bespoke joined procedure.
            foreach (var role in roles)
            {
                var permissionSet = await adminRbacProvider.GetRolePermissionsAsync(role.Name, cancellationToken);

                result.Add(new AdminRoleDto
                {
                    RoleId = role.RoleId,
                    Name = role.Name,
                    Description = role.Description,
                    IsSystemRole = role.IsSystemRole,
                    OperatorCount = role.OperatorCount,
                    Permissions = permissionSet?.Permissions ?? []
                });
            }

            return result;
        });

    public Task<ServiceResult<AdminRoleDto>> GetRolePermissionsAsync(string? sessionToken, string roleName, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await RequireAsync(sessionToken, AdminPermissions.RolesManage, null, cancellationToken);
            return await LoadRoleDtoAsync(roleName, cancellationToken);
        });

    public Task<ServiceResult<AdminWriteResultDto>> CreateRoleAsync(string? sessionToken, AdminRoleCreateRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.RolesManage, clientIp, cancellationToken);

            var mutation = await adminRbacProvider.CreateRoleAsync(request.Name, request.Description, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, $"Role '{request.Name.Trim()}' created.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteRoleAsync(string? sessionToken, string roleName, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.RolesManage, clientIp, cancellationToken);

            var mutation = await adminRbacProvider.DeleteRoleAsync(roleName, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, $"Role '{roleName}' deleted.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> SetRolePermissionAsync(string? sessionToken, AdminRolePermissionRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.RolesManage, clientIp, cancellationToken);

            if (!AdminPermissions.IsKnown(request.Permission))
            {
                throw new ValidationException($"Unknown permission '{request.Permission}' in role permission request.", "That permission does not exist.");
            }

            var mutation = await adminRbacProvider.SetRolePermissionAsync(request.RoleName, request.Permission, request.Granted, actor, cancellationToken);
            var verb = request.Granted ? "granted to" : "revoked from";
            return AdminMutationOutcomeMapper.Resolve(mutation, $"'{request.Permission}' {verb} '{request.RoleName.Trim()}'.");
        });

    public Task<ServiceResult<List<AdminOperatorDto>>> GetOperatorsAsync(string? sessionToken, bool includeInactive, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await RequireAsync(sessionToken, AdminPermissions.OperatorsManage, null, cancellationToken);

            var operators = await adminRbacProvider.GetOperatorsAsync(includeInactive, cancellationToken);
            return operators.Select(ToDto).ToList();
        });

    public Task<ServiceResult<AdminOperatorCreatedDto>> CreateOperatorAsync(string? sessionToken, AdminOperatorCreateRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.OperatorsManage, clientIp, cancellationToken);

            var username = request.Username.Trim();
            if (string.IsNullOrWhiteSpace(username))
            {
                throw new ValidationException("Create-operator called with a blank username.", "A username is required.");
            }

            var email = request.Email.Trim();
            if (string.IsNullOrWhiteSpace(email) || !email.Contains('@'))
            {
                throw new ValidationException("Create-operator called with a missing or malformed email.", "A valid email address is required.");
            }

            if (request.Password.Length < MinimumPasswordLength)
            {
                throw new ValidationException(
                    $"Create-operator password shorter than {MinimumPasswordLength} characters.",
                    $"Choose a password of at least {MinimumPasswordLength} characters.");
            }

            if (!string.IsNullOrWhiteSpace(request.RoleName) && !await RoleExistsAsync(request.RoleName, cancellationToken))
            {
                throw new ValidationException($"Create-operator asked for unknown role '{request.RoleName}'.", $"No role named '{request.RoleName}'.");
            }

            var (passwordHash, passwordSalt) = PasswordHasher.Hash(request.Password);
            var totpSecret = TotpHelper.GenerateSecret();
            var masterKey = AdminTotpSecretCipher.ParseMasterKey(encryptionOptions.Value.MasterKeyBase64);
            var totpSecretCipher = AdminTotpSecretCipher.Encrypt(totpSecret, masterKey);
            var roleName = string.IsNullOrWhiteSpace(request.RoleName) ? null : request.RoleName.Trim();

            var mutation = await adminRbacProvider.CreateOperatorAsync(
                username, passwordHash, passwordSalt, totpSecretCipher, email, roleName, actor, cancellationToken);

            // Reuse the outcome mapper purely for its exception translation (NotFound /
            // Conflict / Rejected -> the matching HTTP status) - its success DTO has no
            // room for an enrollment secret, so the real payload is built below instead.
            _ = AdminMutationOutcomeMapper.Resolve(mutation, "Operator created.");

            var options = adminAuthOptions.Value;

            await SendOperatorEmailConfirmationAsync(mutation.EntityId!.Value, username, email, cancellationToken);

            return new AdminOperatorCreatedDto
            {
                AdminUserId = mutation.EntityId!.Value,
                Username = username,
                RoleName = roleName,
                TotpSecret = totpSecret,
                OtpAuthUri = TotpHelper.BuildOtpAuthUri(options.TotpIssuer, username, totpSecret, options.TotpDigits, options.TotpStepSeconds)
            };
        });

    /// <summary>
    /// Confirms the email a new operator was created with. Deliberately takes no
    /// session token and calls no permission check - the recipient has just
    /// clicked a link from their inbox and may not have signed in yet, so the
    /// signed, time-limited token itself is the authorization (see
    /// <see cref="AdminEmailConfirmTokenFactory"/>).
    /// </summary>
    public Task<ServiceResult<AdminWriteResultDto>> ConfirmOperatorEmailAsync(string token, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var confirm = AdminEmailConfirmTokenFactory.ReadToken(jwtOptions.Value, token)
                ?? throw new UnauthorizedAppException("Operator email confirmation presented an invalid or expired token.", "This confirmation link is invalid or has expired. Ask an admin to resend it.");

            var mutation = await adminRbacProvider.ConfirmOperatorEmailAsync(confirm.AdminUserId, confirm.Email, clientIp, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Email confirmed.");
        });

    private async Task SendOperatorEmailConfirmationAsync(Guid adminUserId, string username, string email, CancellationToken cancellationToken)
    {
        var options = adminAuthOptions.Value;
        var token = AdminEmailConfirmTokenFactory.CreateToken(jwtOptions.Value, adminUserId, email, TimeSpan.FromHours(options.EmailConfirmHours));
        var confirmUrl = $"{options.ConsoleBaseUrl}/confirm-operator-email.html?token={Uri.EscapeDataString(token)}";

        var (subject, html) = OperatorEmailConfirmTemplate.Build(username, confirmUrl);
        await emailSender.SendAsync(email, subject, html, cancellationToken);
    }

    public Task<ServiceResult<AdminWriteResultDto>> SetOperatorRoleAsync(string? sessionToken, AdminOperatorRoleRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.OperatorsManage, clientIp, cancellationToken);

            var mutation = await adminRbacProvider.SetOperatorRoleAsync(request.Username, request.RoleName, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, $"'{request.Username.Trim()}' moved to role '{request.RoleName.Trim()}'.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> SetOperatorActiveAsync(string? sessionToken, AdminOperatorActiveRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await RequireAsync(sessionToken, AdminPermissions.OperatorsManage, clientIp, cancellationToken);

            var mutation = await adminRbacProvider.SetOperatorActiveAsync(request.Username, request.IsActive, actor, cancellationToken);
            var verb = request.IsActive ? "reactivated" : "deactivated";
            return AdminMutationOutcomeMapper.Resolve(mutation, $"'{request.Username.Trim()}' {verb}.");
        });

    public Task<ServiceResult<List<AdminAuditEntryDto>>> GetRecentAuditAsync(string? sessionToken, int limit, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await RequireAsync(sessionToken, AdminPermissions.AuditRead, null, cancellationToken);

            var entries = await adminRbacProvider.GetRecentAuditAsync(limit, cancellationToken);
            return entries.Select(entry => new AdminAuditEntryDto
            {
                AuditId = entry.AuditId,
                Username = entry.Username,
                Action = entry.Action,
                EntityType = entry.EntityType,
                EntityId = entry.EntityId,
                Summary = entry.Summary,
                CreatedFromIp = entry.CreatedFromIp,
                CreatedAtUtc = entry.CreatedAtUtc
            }).ToList();
        });

    private Task<AdminActorModel> RequireAsync(string? sessionToken, string permission, string? clientIp, CancellationToken cancellationToken) =>
        AdminPermissionGuard.RequireAsync(adminProvider, adminRbacProvider, sessionToken, permission, clientIp, cancellationToken);

    private async Task<bool> RoleExistsAsync(string roleName, CancellationToken cancellationToken) =>
        await adminRbacProvider.GetRolePermissionsAsync(roleName.Trim(), cancellationToken) is not null;

    private async Task<AdminRoleDto> LoadRoleDtoAsync(string roleName, CancellationToken cancellationToken)
    {
        var permissionSet = await adminRbacProvider.GetRolePermissionsAsync(roleName, cancellationToken)
            ?? throw new NotFoundException($"No role named '{roleName}'.", $"No role named '{roleName}'.");

        var roles = await adminRbacProvider.GetRolesAsync(cancellationToken);
        var role = roles.First(r => r.Name == permissionSet.RoleName);

        return new AdminRoleDto
        {
            RoleId = role.RoleId,
            Name = role.Name,
            Description = role.Description,
            IsSystemRole = role.IsSystemRole,
            OperatorCount = role.OperatorCount,
            Permissions = permissionSet.Permissions
        };
    }

    private static AdminOperatorDto ToDto(AdminOperatorModel model) => new()
    {
        AdminUserId = model.AdminUserId,
        Username = model.Username,
        RoleName = model.RoleName,
        IsActive = model.IsActive,
        ActiveSessionCount = model.ActiveSessionCount,
        LastLoginAtUtc = model.LastLoginAtUtc,
        CreatedAtUtc = model.CreatedAtUtc,
        Email = model.Email,
        EmailConfirmed = model.EmailConfirmedAtUtc is not null
    };
}
