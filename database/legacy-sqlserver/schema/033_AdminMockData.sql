USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Mock-data seeding permission.
--
-- The admin console can repopulate one app user's logs with a generated month of
-- workouts, meals, hydration and bodyweight (the same generator behind
-- Silen.Tools.SeedMockData) so the monthly overview can be exercised on demand.
--
-- That action is deliberately destructive: it wipes and regenerates the target
-- user's history and grants them a yearly subscription. So unlike the content
-- permissions, this one is granted to super-admin ONLY - not content-editor,
-- analyst or trainer. A custom role can still be granted it explicitly from the
-- Roles screen if an operator really needs it.
--
-- The permission string is new in this build, so nobody can have deliberately
-- revoked it yet; inserting it here is how an existing deployment picks it up.
-- Re-running is a no-op (NOT EXISTS guard), matching the other migrations.
-- =============================================================================
INSERT INTO dbo.AdminRolePermissions (RoleId, Permission)
SELECT roles.RoleId, N'users.mock_data'
FROM dbo.AdminRoles roles
WHERE roles.Name = N'super-admin'
  AND NOT EXISTS
      (SELECT 1 FROM dbo.AdminRolePermissions existing
       WHERE existing.RoleId = roles.RoleId AND existing.Permission = N'users.mock_data');
GO
