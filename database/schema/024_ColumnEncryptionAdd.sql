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
--
-- Each block is guarded on the table's own "_Legacy" column rather than just
-- "Enc IS NULL": once 025 has cut a table over, its *Enc columns no longer
-- exist (renamed into place), so a bare "Enc IS NULL" guard reads as "not
-- added yet" and resurrects them as fresh, all-NULL columns on every later
-- deploy - which then makes 025's own guard fire again and (harmlessly, but
-- loudly) fail on the rename collision with the "_Legacy" column that's
-- already there, and made the backfill tool below crash reading the real
-- ciphertext back out as if it were still plaintext. "_Legacy" existing is
-- the actual "already cut over" signal, so it both stops the resurrection
-- and - since this ran at least once before this fix landed - drops any
-- stray Enc column an earlier deploy already resurrected.

IF COL_LENGTH(N'dbo.UserProfiles', N'Gender_Legacy') IS NOT NULL
BEGIN
    IF COL_LENGTH(N'dbo.UserProfiles', N'GenderEnc') IS NOT NULL
        ALTER TABLE dbo.UserProfiles DROP COLUMN GenderEnc, AgeYearsEnc, HeightCmEnc, WeightKgEnc, GoalEnc;
END
ELSE IF COL_LENGTH(N'dbo.UserProfiles', N'GenderEnc') IS NULL
BEGIN
    ALTER TABLE dbo.UserProfiles ADD
        GenderEnc   VARBINARY(100) NULL,
        AgeYearsEnc VARBINARY(100) NULL,
        HeightCmEnc VARBINARY(100) NULL,
        WeightKgEnc VARBINARY(100) NULL,
        GoalEnc     VARBINARY(100) NULL;
END
GO

IF COL_LENGTH(N'dbo.BodyweightLogs', N'WeightKg_Legacy') IS NOT NULL
BEGIN
    IF COL_LENGTH(N'dbo.BodyweightLogs', N'WeightKgEnc') IS NOT NULL
        ALTER TABLE dbo.BodyweightLogs DROP COLUMN WeightKgEnc;
END
ELSE IF COL_LENGTH(N'dbo.BodyweightLogs', N'WeightKgEnc') IS NULL
BEGIN
    ALTER TABLE dbo.BodyweightLogs ADD
        WeightKgEnc VARBINARY(64) NULL;
END
GO

IF COL_LENGTH(N'dbo.MealLogs', N'Title_Legacy') IS NOT NULL
BEGIN
    IF COL_LENGTH(N'dbo.MealLogs', N'TitleEnc') IS NOT NULL
        ALTER TABLE dbo.MealLogs DROP COLUMN TitleEnc, CaloriesKcalEnc, ProteinGEnc, CarbsGEnc, FatsGEnc;
END
ELSE IF COL_LENGTH(N'dbo.MealLogs', N'TitleEnc') IS NULL
BEGIN
    ALTER TABLE dbo.MealLogs ADD
        TitleEnc        VARBINARY(300) NULL,
        CaloriesKcalEnc VARBINARY(64)  NULL,
        ProteinGEnc     VARBINARY(64)  NULL,
        CarbsGEnc       VARBINARY(64)  NULL,
        FatsGEnc        VARBINARY(64)  NULL;
END
GO

IF COL_LENGTH(N'dbo.UserNutritionTargets', N'TargetCalories_Legacy') IS NOT NULL
BEGIN
    IF COL_LENGTH(N'dbo.UserNutritionTargets', N'TargetCaloriesEnc') IS NOT NULL
        ALTER TABLE dbo.UserNutritionTargets DROP COLUMN TargetCaloriesEnc, TargetProteinGEnc, TargetCarbsGEnc, TargetFatsGEnc;
END
ELSE IF COL_LENGTH(N'dbo.UserNutritionTargets', N'TargetCaloriesEnc') IS NULL
BEGIN
    ALTER TABLE dbo.UserNutritionTargets ADD
        TargetCaloriesEnc VARBINARY(64) NULL,
        TargetProteinGEnc VARBINARY(64) NULL,
        TargetCarbsGEnc   VARBINARY(64) NULL,
        TargetFatsGEnc    VARBINARY(64) NULL;
END
GO
