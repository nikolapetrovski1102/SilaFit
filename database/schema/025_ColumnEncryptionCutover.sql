USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Step 3 of 3 in the column-encryption rollout. Run this ONLY after:
--   1. database/schema/024_ColumnEncryptionAdd.sql has run, and
--   2. backend/src/Silen.Tools.EncryptExistingData has backfilled every
--      *Enc column and verified row counts / non-null counts match the
--      plaintext columns being replaced.
--
-- Renames the old plaintext columns out of the way (kept, not dropped, so
-- there's a rollback path) and promotes the *Enc columns to the real
-- column names. CHECK constraints on the plaintext columns being renamed
-- (e.g. CK_UserProfiles_Gender) stay attached to the renamed-away column,
-- so they keep validating the legacy plaintext data harmlessly.
--
-- Deploy the updated backend (Providers/procs reading the new VARBINARY
-- columns under their original names) immediately after this script -
-- until then, the app is reading/writing columns that no longer match its
-- procs. database/manual-migrations/026_ColumnEncryptionCleanup.sql drops
-- the "_Legacy" columns for good, once the new build has run cleanly in
-- production for a few days. It deliberately lives outside database/schema/
-- so deploy.sh's automatic loop never runs it - see that file's header for
-- how to run it manually.

IF COL_LENGTH(N'dbo.UserProfiles', N'Gender') IS NOT NULL AND COL_LENGTH(N'dbo.UserProfiles', N'GenderEnc') IS NOT NULL
BEGIN
    -- sp_rename refuses to rename a column an enforced CHECK constraint
    -- depends on (error 15336), so the constraints have to be dropped before
    -- the rename and rebuilt against the renamed-away column afterward -
    -- they can't just "come along" automatically. Same names, so
    -- database/manual-migrations/026_ColumnEncryptionCleanup.sql still finds
    -- and drops them by name later.
    IF OBJECT_ID(N'dbo.CK_UserProfiles_Gender', N'C') IS NOT NULL
        ALTER TABLE dbo.UserProfiles DROP CONSTRAINT CK_UserProfiles_Gender;
    IF OBJECT_ID(N'dbo.CK_UserProfiles_Goal', N'C') IS NOT NULL
        ALTER TABLE dbo.UserProfiles DROP CONSTRAINT CK_UserProfiles_Goal;

    EXEC sp_rename N'dbo.UserProfiles.Gender', N'Gender_Legacy', N'COLUMN';
    EXEC sp_rename N'dbo.UserProfiles.AgeYears', N'AgeYears_Legacy', N'COLUMN';
    EXEC sp_rename N'dbo.UserProfiles.HeightCm', N'HeightCm_Legacy', N'COLUMN';
    EXEC sp_rename N'dbo.UserProfiles.WeightKg', N'WeightKg_Legacy', N'COLUMN';
    EXEC sp_rename N'dbo.UserProfiles.Goal', N'Goal_Legacy', N'COLUMN';

    EXEC sp_rename N'dbo.UserProfiles.GenderEnc', N'Gender', N'COLUMN';
    EXEC sp_rename N'dbo.UserProfiles.AgeYearsEnc', N'AgeYears', N'COLUMN';
    EXEC sp_rename N'dbo.UserProfiles.HeightCmEnc', N'HeightCm', N'COLUMN';
    EXEC sp_rename N'dbo.UserProfiles.WeightKgEnc', N'WeightKg', N'COLUMN';
    EXEC sp_rename N'dbo.UserProfiles.GoalEnc', N'Goal', N'COLUMN';

    -- Dynamic SQL: the batch is bound as a whole before it starts running, so
    -- an inline ALTER TABLE ... ADD CONSTRAINT here would still resolve
    -- Gender_Legacy/Goal_Legacy against the pre-rename schema and fail with
    -- "Invalid column name". EXEC forces a fresh compile after the renames
    -- above have actually run.
    EXEC(N'ALTER TABLE dbo.UserProfiles ADD CONSTRAINT CK_UserProfiles_Gender
        CHECK (Gender_Legacy = ''Other'' OR Gender_Legacy = ''Female'' OR Gender_Legacy = ''Male'');');
    EXEC(N'ALTER TABLE dbo.UserProfiles ADD CONSTRAINT CK_UserProfiles_Goal
        CHECK (Goal_Legacy = ''MaintainActive'' OR Goal_Legacy = ''LoseFat'' OR Goal_Legacy = ''BuildMuscle'');');
END
GO

IF COL_LENGTH(N'dbo.BodyweightLogs', N'WeightKgEnc') IS NOT NULL
BEGIN
    -- Same enforced-dependency issue as UserProfiles above: CK_BodyweightLogs_WeightKg
    -- has to be dropped before the rename and rebuilt against the renamed-away column.
    IF OBJECT_ID(N'dbo.CK_BodyweightLogs_WeightKg', N'C') IS NOT NULL
        ALTER TABLE dbo.BodyweightLogs DROP CONSTRAINT CK_BodyweightLogs_WeightKg;

    EXEC sp_rename N'dbo.BodyweightLogs.WeightKg', N'WeightKg_Legacy', N'COLUMN';
    EXEC sp_rename N'dbo.BodyweightLogs.WeightKgEnc', N'WeightKg', N'COLUMN';

    EXEC(N'ALTER TABLE dbo.BodyweightLogs ADD CONSTRAINT CK_BodyweightLogs_WeightKg
        CHECK (WeightKg_Legacy > 0);');
END
GO

IF COL_LENGTH(N'dbo.MealLogs', N'TitleEnc') IS NOT NULL
BEGIN
    EXEC sp_rename N'dbo.MealLogs.Title', N'Title_Legacy', N'COLUMN';
    EXEC sp_rename N'dbo.MealLogs.CaloriesKcal', N'CaloriesKcal_Legacy', N'COLUMN';
    EXEC sp_rename N'dbo.MealLogs.ProteinG', N'ProteinG_Legacy', N'COLUMN';
    EXEC sp_rename N'dbo.MealLogs.CarbsG', N'CarbsG_Legacy', N'COLUMN';
    EXEC sp_rename N'dbo.MealLogs.FatsG', N'FatsG_Legacy', N'COLUMN';

    EXEC sp_rename N'dbo.MealLogs.TitleEnc', N'Title', N'COLUMN';
    EXEC sp_rename N'dbo.MealLogs.CaloriesKcalEnc', N'CaloriesKcal', N'COLUMN';
    EXEC sp_rename N'dbo.MealLogs.ProteinGEnc', N'ProteinG', N'COLUMN';
    EXEC sp_rename N'dbo.MealLogs.CarbsGEnc', N'CarbsG', N'COLUMN';
    EXEC sp_rename N'dbo.MealLogs.FatsGEnc', N'FatsG', N'COLUMN';
END
GO

IF COL_LENGTH(N'dbo.UserNutritionTargets', N'TargetCaloriesEnc') IS NOT NULL
BEGIN
    EXEC sp_rename N'dbo.UserNutritionTargets.TargetCalories', N'TargetCalories_Legacy', N'COLUMN';
    EXEC sp_rename N'dbo.UserNutritionTargets.TargetProteinG', N'TargetProteinG_Legacy', N'COLUMN';
    EXEC sp_rename N'dbo.UserNutritionTargets.TargetCarbsG', N'TargetCarbsG_Legacy', N'COLUMN';
    EXEC sp_rename N'dbo.UserNutritionTargets.TargetFatsG', N'TargetFatsG_Legacy', N'COLUMN';

    EXEC sp_rename N'dbo.UserNutritionTargets.TargetCaloriesEnc', N'TargetCalories', N'COLUMN';
    EXEC sp_rename N'dbo.UserNutritionTargets.TargetProteinGEnc', N'TargetProteinG', N'COLUMN';
    EXEC sp_rename N'dbo.UserNutritionTargets.TargetCarbsGEnc', N'TargetCarbsG', N'COLUMN';
    EXEC sp_rename N'dbo.UserNutritionTargets.TargetFatsGEnc', N'TargetFatsG', N'COLUMN';
END
GO
