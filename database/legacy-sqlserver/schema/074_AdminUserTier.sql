USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Manual tier changes from the console.
--
-- users.subscription.write lets an operator move one app user onto Free, Pro or
-- Advanced without a store purchase (comps, support fixes, testing) - see
-- usp_Admin_User_SetPlan in procedures/AdminContent.sql. It hands out paid
-- features for free, so it is reserved for super-admin: the role editor refuses
-- to grant it to any other role (AdminPermissions.SuperAdminOnly).
--
-- The permission string is new in this build, so nobody can have deliberately
-- revoked it yet; inserting it here is how an existing deployment picks it up.
-- Re-running is a no-op (NOT EXISTS guard), matching the other migrations.
-- =============================================================================
INSERT INTO dbo.AdminRolePermissions (RoleId, Permission)
SELECT roles.RoleId, N'users.subscription.write'
FROM dbo.AdminRoles roles
WHERE roles.Name = N'super-admin'
  AND NOT EXISTS
      (SELECT 1 FROM dbo.AdminRolePermissions existing
       WHERE existing.RoleId = roles.RoleId AND existing.Permission = N'users.subscription.write');
GO

-- Reserved for super-admin: strip it from every other role, so a grant made by
-- hand (or before the API refused it) does not survive a deploy.
DELETE perms
FROM dbo.AdminRolePermissions perms
INNER JOIN dbo.AdminRoles roles ON roles.RoleId = perms.RoleId
WHERE perms.Permission = N'users.subscription.write'
  AND roles.Name <> N'super-admin';
GO
