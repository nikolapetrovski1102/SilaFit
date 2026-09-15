USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Trainer-owned splits + visibility.
--
-- Until now every row in WorkoutSplits was reference content: one library, the
-- same for everybody. This adds the pieces a gym trainer needs to author their
-- own protocols and hand them to paying clients:
--
--   OwnerAdminUserId  who wrote the split (NULL = shipped/legacy content)
--   Visibility        who may see it in the app:
--                       Public  - every app user (the old behaviour)
--                       Shared  - only users it has been assigned to
--                       Private - only the owning trainer; no app user sees it
--   SplitAssignments  one row per (split, user): the trainer gave this user the
--                     protocol. A row is both the visibility grant and the
--                     "assigned to" record the console lists.
--
-- The app-side procedures in procedures/Splits.sql read these columns; the
-- console-side procedures in procedures/AdminSplits.sql write them. Nothing here
-- changes how WorkoutSplits/SplitDays/SplitDayExercises are shaped.
-- =============================================================================

-- Each DDL step is its own batch (GO): a column added in one batch is not
-- visible to statements later in the *same* batch, so the FK/index/check must be
-- compiled only after the ADD has committed. The constraint/index guards are
-- deliberately independent of the column guard, so a half-applied migration
-- (column present but its constraint/index missing) is repaired by re-running.
IF COL_LENGTH(N'dbo.WorkoutSplits', N'OwnerAdminUserId') IS NULL
BEGIN
    ALTER TABLE dbo.WorkoutSplits ADD OwnerAdminUserId UNIQUEIDENTIFIER NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_WorkoutSplits_AdminUsers')
BEGIN
    ALTER TABLE dbo.WorkoutSplits ADD CONSTRAINT FK_WorkoutSplits_AdminUsers
        FOREIGN KEY (OwnerAdminUserId) REFERENCES dbo.AdminUsers(AdminUserId) ON DELETE SET NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_WorkoutSplits_OwnerAdminUserId')
BEGIN
    CREATE INDEX IX_WorkoutSplits_OwnerAdminUserId ON dbo.WorkoutSplits(OwnerAdminUserId);
END
GO

IF COL_LENGTH(N'dbo.WorkoutSplits', N'Visibility') IS NULL
BEGIN
    -- 'Public' default matches the pre-existing behaviour: every split that was
    -- in the library before this migration stays visible to every app user.
    ALTER TABLE dbo.WorkoutSplits ADD Visibility NVARCHAR(20) NOT NULL
        CONSTRAINT DF_WorkoutSplits_Visibility DEFAULT (N'Public');
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_WorkoutSplits_Visibility')
BEGIN
    ALTER TABLE dbo.WorkoutSplits ADD CONSTRAINT CK_WorkoutSplits_Visibility
        CHECK (Visibility IN (N'Private', N'Public', N'Shared'));
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_WorkoutSplits_Visibility')
BEGIN
    CREATE INDEX IX_WorkoutSplits_Visibility ON dbo.WorkoutSplits(Visibility);
END
GO

IF OBJECT_ID(N'dbo.SplitAssignments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SplitAssignments
    (
        SplitId               UNIQUEIDENTIFIER NOT NULL,
        UserId                UNIQUEIDENTIFIER NOT NULL,
        AssignedByAdminUserId UNIQUEIDENTIFIER NULL,
        AssignedAtUtc         DATETIME2(3)     NOT NULL CONSTRAINT DF_SplitAssignments_AssignedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_SplitAssignments PRIMARY KEY CLUSTERED (SplitId, UserId),
        -- Deleting a split is already blocked while any user has it active (see
        -- usp_Admin_Split_Delete); the cascade only cleans up dormant grants.
        CONSTRAINT FK_SplitAssignments_WorkoutSplits FOREIGN KEY (SplitId)
            REFERENCES dbo.WorkoutSplits(SplitId) ON DELETE CASCADE,
        CONSTRAINT FK_SplitAssignments_Users FOREIGN KEY (UserId)
            REFERENCES dbo.Users(UserId),
        CONSTRAINT FK_SplitAssignments_AdminUsers FOREIGN KEY (AssignedByAdminUserId)
            REFERENCES dbo.AdminUsers(AdminUserId) ON DELETE SET NULL
    );

    -- The app-side list procedure filters "splits assigned to *me*", which is a
    -- seek on UserId; the PK already covers "assignments of this split".
    CREATE INDEX IX_SplitAssignments_UserId ON dbo.SplitAssignments(UserId);
END
GO

-- =============================================================================
-- New split permissions + the trainer role.
--
-- The two permission strings are new in this build, so no operator can have
-- deliberately revoked them yet - granting them to the shipped system roles here
-- is safe and is how an existing deployment picks up the capability. The
-- trainer role is separate from content-editor on purpose: a trainer authors and
-- assigns their *own* splits, and content.splits.manage_all (which they do not
-- hold) is what lets an operator touch someone else's.
-- =============================================================================
INSERT INTO dbo.AdminRolePermissions (RoleId, Permission)
SELECT roles.RoleId, grants.Permission
FROM dbo.AdminRoles roles
CROSS JOIN (VALUES (N'content.splits.assign'), (N'content.splits.manage_all')) AS grants (Permission)
WHERE roles.Name IN (N'super-admin', N'content-editor')
  AND NOT EXISTS
      (SELECT 1 FROM dbo.AdminRolePermissions existing
       WHERE existing.RoleId = roles.RoleId AND existing.Permission = grants.Permission);
GO

DECLARE @TrainerRoleId UNIQUEIDENTIFIER =
    (SELECT RoleId FROM dbo.AdminRoles WHERE Name = N'trainer');

IF @TrainerRoleId IS NULL
BEGIN
    SET @TrainerRoleId = NEWID();

    INSERT INTO dbo.AdminRoles (RoleId, Name, Description, IsSystemRole)
    VALUES (@TrainerRoleId, N'trainer',
            N'Gym trainer: author their own workout splits and assign them to clients.', 1);
END

-- A trainer needs to pick exercises (read, not write) and to find clients in
-- the user list (users.read - tier/subscription only, never anyone's logs).
INSERT INTO dbo.AdminRolePermissions (RoleId, Permission)
SELECT @TrainerRoleId, grants.Permission
FROM (VALUES
    (N'content.splits.read'),
    (N'content.splits.write'),
    (N'content.splits.assign'),
    (N'content.exercises.read'),
    (N'users.read')
) AS grants (Permission)
WHERE NOT EXISTS
    (SELECT 1 FROM dbo.AdminRolePermissions existing
     WHERE existing.RoleId = @TrainerRoleId AND existing.Permission = grants.Permission);
GO
