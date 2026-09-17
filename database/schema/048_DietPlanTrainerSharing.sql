USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Trainer/user grant + visibility-unlock record, mirroring dbo.SplitAssignments.
IF OBJECT_ID(N'dbo.DietPlanAssignments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DietPlanAssignments
    (
        DietPlanId            UNIQUEIDENTIFIER NOT NULL,
        UserId                UNIQUEIDENTIFIER NOT NULL,
        AssignedByAdminUserId UNIQUEIDENTIFIER NULL,
        AssignedAtUtc         DATETIME2(3)     NOT NULL CONSTRAINT DF_DietPlanAssignments_AssignedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_DietPlanAssignments PRIMARY KEY CLUSTERED (DietPlanId, UserId),
        CONSTRAINT FK_DietPlanAssignments_DietPlans FOREIGN KEY (DietPlanId)
            REFERENCES dbo.NutritionPlans(DietPlanId) ON DELETE CASCADE,
        CONSTRAINT FK_DietPlanAssignments_Users FOREIGN KEY (UserId)
            REFERENCES dbo.Users(UserId),
        CONSTRAINT FK_DietPlanAssignments_AdminUsers FOREIGN KEY (AssignedByAdminUserId)
            REFERENCES dbo.AdminUsers(AdminUserId) ON DELETE SET NULL
    );

    CREATE INDEX IX_DietPlanAssignments_UserId ON dbo.DietPlanAssignments(UserId);
END
GO

-- Which diet plan is a user's current one, mirroring dbo.UserActiveSplits.
-- Deliberately NOT wired into dbo.MealLogs yet in this phase - "activating" a
-- plan is just a label for now (see the write side in UserDietPlans.sql /
-- AdminDietPlans.sql); whether activation should pre-populate MealLogs is a
-- separate product decision for later.
IF OBJECT_ID(N'dbo.UserActiveDietPlans', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserActiveDietPlans
    (
        UserId        UNIQUEIDENTIFIER NOT NULL,
        DietPlanId    UNIQUEIDENTIFIER NOT NULL,
        ActivatedAtUtc DATETIME2(3)    NOT NULL CONSTRAINT DF_UserActiveDietPlans_ActivatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_UserActiveDietPlans PRIMARY KEY CLUSTERED (UserId),
        CONSTRAINT FK_UserActiveDietPlans_Users FOREIGN KEY (UserId)
            REFERENCES dbo.Users(UserId),
        CONSTRAINT FK_UserActiveDietPlans_DietPlans FOREIGN KEY (DietPlanId)
            REFERENCES dbo.NutritionPlans(DietPlanId)
    );
END
GO

-- =============================================================================
-- Diet-plan permissions, granted to the same roles as the split equivalents
-- (see 031_SplitTrainerSharing.sql:102-148).
-- =============================================================================
INSERT INTO dbo.AdminRolePermissions (RoleId, Permission)
SELECT roles.RoleId, grants.Permission
FROM dbo.AdminRoles roles
CROSS JOIN (VALUES
    (N'content.diet_plans.read'),
    (N'content.diet_plans.write'),
    (N'content.diet_plans.assign'),
    (N'content.diet_plans.manage_all')
) AS grants (Permission)
WHERE roles.Name IN (N'super-admin', N'content-editor')
  AND NOT EXISTS
      (SELECT 1 FROM dbo.AdminRolePermissions existing
       WHERE existing.RoleId = roles.RoleId AND existing.Permission = grants.Permission);
GO

DECLARE @TrainerRoleId UNIQUEIDENTIFIER =
    (SELECT RoleId FROM dbo.AdminRoles WHERE Name = N'trainer');

IF @TrainerRoleId IS NOT NULL
BEGIN
    INSERT INTO dbo.AdminRolePermissions (RoleId, Permission)
    SELECT @TrainerRoleId, grants.Permission
    FROM (VALUES
        (N'content.diet_plans.read'),
        (N'content.diet_plans.write'),
        (N'content.diet_plans.assign')
    ) AS grants (Permission)
    WHERE NOT EXISTS
        (SELECT 1 FROM dbo.AdminRolePermissions existing
         WHERE existing.RoleId = @TrainerRoleId AND existing.Permission = grants.Permission);
END
GO
