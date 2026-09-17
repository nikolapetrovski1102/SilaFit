using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;

namespace Silen.Services.Helpers;

/// <summary>
/// Resolves a session cookie into the operator behind it and checks the one
/// permission the calling endpoint needs, in a single place so every RBAC-service
/// method enforces access the same way.
///
/// A session that doesn't resolve is a 401 (from <see cref="AdminSessionResolver"/>
/// - "sign in again"); a session that resolves but lacks the permission is a 403
/// (<see cref="ForbiddenException"/> - "this isn't yours to do"). Permissions are
/// re-read from the role on every call, never cached, so a revoked permission stops
/// working on the very next request rather than at the next sign-in.
/// </summary>
public static class AdminPermissionGuard
{
    public static async Task<AdminActorModel> RequireAsync(
        IAdminProvider adminProvider,
        IAdminRbacProvider adminRbacProvider,
        string? sessionToken,
        string permission,
        string? clientIp,
        CancellationToken cancellationToken)
    {
        var (actor, _) = await RequireWithPermissionsAsync(
            adminProvider, adminRbacProvider, sessionToken, permission, clientIp, cancellationToken);

        return actor;
    }

    /// <summary>
    /// Same check as <see cref="RequireAsync"/>, but also hands back the operator's
    /// whole permission set. The split endpoints need more than the one permission
    /// that gated the call - content.splits.manage_all changes whether the actor may
    /// touch a split they don't own - and re-deriving the session would mean a second
    /// lookup on every request.
    /// </summary>
    public static async Task<(AdminActorModel Actor, IReadOnlySet<string> Permissions)> RequireWithPermissionsAsync(
        IAdminProvider adminProvider,
        IAdminRbacProvider adminRbacProvider,
        string? sessionToken,
        string permission,
        string? clientIp,
        CancellationToken cancellationToken)
    {
        var session = await AdminSessionResolver.ResolveOrThrowAsync(adminProvider, sessionToken, cancellationToken);
        var permissions = await adminRbacProvider.GetPermissionsAsync(session.AdminUserId, cancellationToken);

        if (!permissions.Contains(permission))
        {
            throw new ForbiddenException($"Operator tag {LogRedaction.Tag(session.Username)} called an endpoint requiring '{permission}' without it.");
        }

        var actor = new AdminActorModel
        {
            AdminUserId = session.AdminUserId,
            Username = session.Username,
            Ip = clientIp
        };

        return (actor, new HashSet<string>(permissions, StringComparer.Ordinal));
    }

    /// <summary>
    /// Same resolution and actor shape as <see cref="RequireWithPermissionsAsync"/>, but
    /// passes when the operator holds *any* one of the supplied permissions.
    ///
    /// This exists for the two content-library reads that other editors depend on: an
    /// operator allowed to edit splits still has to populate the split-day exercise
    /// picker, and one allowed to edit diet plans still has to populate the meal-slot
    /// picker - whether or not they also hold the library's own read permission. Gating
    /// those reads on `.read` alone left write-only operators with empty dropdowns and
    /// a message wrongly claiming the library itself was empty.
    /// </summary>
    public static async Task<(AdminActorModel Actor, IReadOnlySet<string> Permissions)> RequireAnyAsync(
        IAdminProvider adminProvider,
        IAdminRbacProvider adminRbacProvider,
        string? sessionToken,
        IReadOnlyCollection<string> permissions,
        string? clientIp,
        CancellationToken cancellationToken)
    {
        var session = await AdminSessionResolver.ResolveOrThrowAsync(adminProvider, sessionToken, cancellationToken);
        var granted = await adminRbacProvider.GetPermissionsAsync(session.AdminUserId, cancellationToken);

        if (!permissions.Any(granted.Contains))
        {
            throw new ForbiddenException(
                $"Operator tag {LogRedaction.Tag(session.Username)} called an endpoint requiring one of " +
                $"'{string.Join("', '", permissions)}' without holding any of them.");
        }

        var actor = new AdminActorModel
        {
            AdminUserId = session.AdminUserId,
            Username = session.Username,
            Ip = clientIp
        };

        return (actor, new HashSet<string>(granted, StringComparer.Ordinal));
    }
}
