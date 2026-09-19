USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Client-log read access for the console.
--
-- users.read only ever covered tier/join-date/subscription (see 028/031). Seeing
-- what a person actually logged - their workouts and sets, meals, bodyweight and
-- hydration - is a separate capability, so it gets its own permission:
--
--   users.data.read      open a client overview for a user who is your client
--   users.data.read_all  open the overview for ANY user, client or not
--
-- super-admin and analyst hold both; the shipped trainer role holds only
-- users.data.read, so a trainer's assigned-client list stays the boundary of
-- what they can see. These strings are new in this build, so nobody can have
-- deliberately revoked them yet - granting them to the shipped system roles here
-- is how an existing deployment picks up the capability. The NOT EXISTS guard
-- keeps re-deploys from resurrecting a permission an operator later removed.
-- =============================================================================
INSERT INTO dbo.AdminRolePermissions (RoleId, Permission)
SELECT roles.RoleId, grants.Permission
FROM dbo.AdminRoles roles
CROSS JOIN (VALUES (N'users.data.read'), (N'users.data.read_all')) AS grants (Permission)
WHERE roles.Name IN (N'super-admin', N'analyst')
  AND NOT EXISTS
      (SELECT 1 FROM dbo.AdminRolePermissions existing
       WHERE existing.RoleId = roles.RoleId AND existing.Permission = grants.Permission);
GO

-- trainer: read their clients' logs, but not anyone else's.
INSERT INTO dbo.AdminRolePermissions (RoleId, Permission)
SELECT roles.RoleId, N'users.data.read'
FROM dbo.AdminRoles roles
WHERE roles.Name = N'trainer'
  AND NOT EXISTS
      (SELECT 1 FROM dbo.AdminRolePermissions existing
       WHERE existing.RoleId = roles.RoleId AND existing.Permission = N'users.data.read');
GO

-- The overview filters set logs by user + completed date, which the existing
-- (UserId, ExerciseId, WeightKg, CompletedAtUtc) index does not serve (ExerciseId
-- sits between the two columns it needs).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_WorkoutSetLogs_UserId_CompletedAtUtc')
BEGIN
    CREATE INDEX IX_WorkoutSetLogs_UserId_CompletedAtUtc
        ON dbo.WorkoutSetLogs(UserId, CompletedAtUtc);
END
GO
