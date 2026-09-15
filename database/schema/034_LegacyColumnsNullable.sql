USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- The column-encryption cutover (025_ColumnEncryptionCutover.sql) renamed the old
-- plaintext columns to *_Legacy and promoted the encrypted *Enc columns into the
-- real names - but the renamed-away columns kept their original NOT NULL
-- constraints. Nothing writes them any more, so every INSERT that only supplies
-- the new encrypted columns failed with:
--   Cannot insert the value NULL into column '<x>_Legacy', table 'SilenDb.dbo.<t>'
-- That breaks the real app paths (usp_MealLogs_Upsert, bodyweight logging,
-- nutrition-target upserts), not just the mock-data seeder.
--
-- This makes the still-NOT NULL *_Legacy columns nullable so writes work again,
-- while the plaintext rollback copies are retained. It deliberately does NOT drop
-- them - that is the deferred database/manual-migrations/026_ColumnEncryptionCleanup.sql,
-- run once 025 has been stable in production.
--
-- Idempotent: each table's block runs only while one of its Legacy columns is
-- still NOT NULL, and ALTER COLUMN ... NULL is a harmless no-op for any column
-- that is already nullable. UserProfiles.*_Legacy were already nullable and are
-- intentionally absent.

IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID(N'dbo.BodyweightLogs')
             AND name = N'WeightKg_Legacy' AND is_nullable = 0)
BEGIN
    ALTER TABLE dbo.BodyweightLogs ALTER COLUMN WeightKg_Legacy DECIMAL(5, 2) NULL;
END
GO

IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID(N'dbo.MealLogs')
             AND name IN (N'Title_Legacy', N'CaloriesKcal_Legacy', N'ProteinG_Legacy', N'CarbsG_Legacy', N'FatsG_Legacy')
             AND is_nullable = 0)
BEGIN
    ALTER TABLE dbo.MealLogs ALTER COLUMN Title_Legacy NVARCHAR(200) NULL;
    ALTER TABLE dbo.MealLogs ALTER COLUMN CaloriesKcal_Legacy SMALLINT NULL;
    ALTER TABLE dbo.MealLogs ALTER COLUMN ProteinG_Legacy SMALLINT NULL;
    ALTER TABLE dbo.MealLogs ALTER COLUMN CarbsG_Legacy SMALLINT NULL;
    ALTER TABLE dbo.MealLogs ALTER COLUMN FatsG_Legacy SMALLINT NULL;
END
GO

IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID(N'dbo.UserNutritionTargets')
             AND name IN (N'TargetCalories_Legacy', N'TargetProteinG_Legacy', N'TargetCarbsG_Legacy', N'TargetFatsG_Legacy')
             AND is_nullable = 0)
BEGIN
    ALTER TABLE dbo.UserNutritionTargets ALTER COLUMN TargetCalories_Legacy SMALLINT NULL;
    ALTER TABLE dbo.UserNutritionTargets ALTER COLUMN TargetProteinG_Legacy SMALLINT NULL;
    ALTER TABLE dbo.UserNutritionTargets ALTER COLUMN TargetCarbsG_Legacy SMALLINT NULL;
    ALTER TABLE dbo.UserNutritionTargets ALTER COLUMN TargetFatsG_Legacy SMALLINT NULL;
END
GO
