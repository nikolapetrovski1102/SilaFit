USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Step 1 of 3 in the column-encryption rollout (see
-- database/schema/025_ColumnEncryptionCutover.sql and
-- backend/src/Silen.Tools.EncryptExistingData). Additive only: introduces
-- the VARBINARY sibling columns that will hold AES-256-GCM ciphertext
-- (Silen.Common.Helpers.FieldCipher), nullable and unused by the running
-- app until the cutover step renames them into place. Safe to run against a
-- live database with real rows - nothing existing changes.

IF COL_LENGTH(N'dbo.UserProfiles', N'GenderEnc') IS NULL
BEGIN
    ALTER TABLE dbo.UserProfiles ADD
        GenderEnc   VARBINARY(100) NULL,
        AgeYearsEnc VARBINARY(100) NULL,
        HeightCmEnc VARBINARY(100) NULL,
        WeightKgEnc VARBINARY(100) NULL,
        GoalEnc     VARBINARY(100) NULL;
END
GO

IF COL_LENGTH(N'dbo.BodyweightLogs', N'WeightKgEnc') IS NULL
BEGIN
    ALTER TABLE dbo.BodyweightLogs ADD
        WeightKgEnc VARBINARY(64) NULL;
END
GO

IF COL_LENGTH(N'dbo.MealLogs', N'TitleEnc') IS NULL
BEGIN
    ALTER TABLE dbo.MealLogs ADD
        TitleEnc        VARBINARY(300) NULL,
        CaloriesKcalEnc VARBINARY(64)  NULL,
        ProteinGEnc     VARBINARY(64)  NULL,
        CarbsGEnc       VARBINARY(64)  NULL,
        FatsGEnc        VARBINARY(64)  NULL;
END
GO

IF COL_LENGTH(N'dbo.UserNutritionTargets', N'TargetCaloriesEnc') IS NULL
BEGIN
    ALTER TABLE dbo.UserNutritionTargets ADD
        TargetCaloriesEnc VARBINARY(64) NULL,
        TargetProteinGEnc VARBINARY(64) NULL,
        TargetCarbsGEnc   VARBINARY(64) NULL,
        TargetFatsGEnc    VARBINARY(64) NULL;
END
GO
