USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Diet plans: a weekly/monthly meal schedule, buildable by a trainer (via the
-- admin console) or by a user for themselves (in the app) - the meal-planning
-- equivalent of dbo.WorkoutSplits, field-for-field mirroring its ownership and
-- visibility shape (see 031_SplitTrainerSharing.sql / 044_WorkoutSplitsUserOwnership.sql)
-- so the same "owned by trainer XOR owned by user XOR shipped system content"
-- rules apply.
--
-- PeriodType is display/filter metadata only ("Weekly" vs "Monthly") - the
-- actual cycle length is DurationDays, the same single-column approach
-- WorkoutSplits already uses, so a "weekly" plan is just one whose days repeat
-- over a 7-day DurationDays and a "monthly" one a longer DurationDays.
--
-- Table is named NutritionPlans, not DietPlans: dbo.DietPlans already exists
-- (036_ImportedContentLibrary.sql) as an unrelated long-form "imported diet
-- guide" article table (Title/Summary/ContentText/SourceUrl, seeded by
-- seed/006_ImportMuscleAndStrength.sql) with none of this feature's columns.
-- The PK/FK column is still named DietPlanId throughout this feature's tables
-- and procedures/C#/admin JS - only the physical table identifier differs -
-- since nothing outside SQL ever references the table name directly.
-- =============================================================================

IF OBJECT_ID(N'dbo.NutritionPlans', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.NutritionPlans
    (
        DietPlanId       UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_NutritionPlans_DietPlanId DEFAULT (NEWID()),
        Name              NVARCHAR(200)    NOT NULL,
        Description       NVARCHAR(1000)   NULL,
        HeroImageUrl      NVARCHAR(500)    NULL,
        PeriodType        NVARCHAR(20)     NOT NULL CONSTRAINT DF_NutritionPlans_PeriodType DEFAULT (N'Weekly'),
        DurationDays      TINYINT          NOT NULL CONSTRAINT DF_NutritionPlans_DurationDays DEFAULT (7),
        IsSystemDefault   BIT              NOT NULL CONSTRAINT DF_NutritionPlans_IsSystemDefault DEFAULT (0),
        SortOrder         INT              NOT NULL CONSTRAINT DF_NutritionPlans_SortOrder DEFAULT (0),
        CreatedAtUtc      DATETIME2(3)     NOT NULL CONSTRAINT DF_NutritionPlans_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),

        -- Owner axes - mirrors WorkoutSplits: at most one of the two is set.
        OwnerAdminUserId  UNIQUEIDENTIFIER NULL,
        OwnerUserId       UNIQUEIDENTIFIER NULL,

        -- Who may see this plan in the app: 'Public' (everyone), 'Shared'
        -- (assigned users only) or 'Private' (its owner only).
        Visibility        NVARCHAR(20)     NOT NULL CONSTRAINT DF_NutritionPlans_Visibility DEFAULT (N'Public'),

        CONSTRAINT PK_NutritionPlans PRIMARY KEY CLUSTERED (DietPlanId),
        CONSTRAINT CK_NutritionPlans_PeriodType CHECK (PeriodType IN (N'Weekly', N'Monthly')),
        CONSTRAINT CK_NutritionPlans_DurationDays CHECK (DurationDays BETWEEN 1 AND 31),
        CONSTRAINT CK_NutritionPlans_Visibility CHECK (Visibility IN (N'Private', N'Public', N'Shared')),
        CONSTRAINT CK_NutritionPlans_OwnerAxis CHECK (OwnerAdminUserId IS NULL OR OwnerUserId IS NULL),
        CONSTRAINT FK_NutritionPlans_AdminUsers FOREIGN KEY (OwnerAdminUserId)
            REFERENCES dbo.AdminUsers(AdminUserId) ON DELETE SET NULL,
        -- No cascade/set-null from Users, matching WorkoutSplits.OwnerUserId -
        -- cleanup happens explicitly in usp_Account_Delete.
        CONSTRAINT FK_NutritionPlans_Users FOREIGN KEY (OwnerUserId)
            REFERENCES dbo.Users(UserId)
    );

    CREATE INDEX IX_NutritionPlans_OwnerAdminUserId ON dbo.NutritionPlans(OwnerAdminUserId);
    CREATE INDEX IX_NutritionPlans_OwnerUserId ON dbo.NutritionPlans(OwnerUserId);
    CREATE INDEX IX_NutritionPlans_Visibility ON dbo.NutritionPlans(Visibility);
END
GO
