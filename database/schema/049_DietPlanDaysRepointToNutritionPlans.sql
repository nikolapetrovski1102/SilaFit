USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Corrective migration for an environment that already ran 046_DietPlanDays.sql /
-- 048_DietPlanTrainerSharing.sql before the dbo.DietPlans naming collision (see
-- 045_DietPlans.sql's header comment) was caught: dbo.DietPlans already existed
-- as the unrelated 036_ImportedContentLibrary.sql table, so 045's CREATE TABLE
-- for the real diet-plans feature was skipped (its OBJECT_ID guard saw the old
-- table and no-opped), while 046/048 still successfully created
-- DietPlanDays/DietPlanAssignments/UserActiveDietPlans with FKs pointing at
-- that wrong, unrelated dbo.DietPlans. Repoints them at dbo.NutritionPlans
-- (045's corrected name) instead. Safe to run on a fresh environment too -
-- every step here is a guarded no-op there, since 046/048 there already point
-- at dbo.NutritionPlans directly.
--
-- No data-loss risk: this feature never shipped, so DietPlanDays/
-- DietPlanAssignments/UserActiveDietPlans are guaranteed empty everywhere this
-- runs - nothing to re-key, just constraint metadata to fix.

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DietPlanDays_DietPlans'
           AND referenced_object_id = OBJECT_ID(N'dbo.DietPlans'))
BEGIN
    ALTER TABLE dbo.DietPlanDays DROP CONSTRAINT FK_DietPlanDays_DietPlans;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DietPlanDays_DietPlans')
BEGIN
    ALTER TABLE dbo.DietPlanDays
        ADD CONSTRAINT FK_DietPlanDays_DietPlans FOREIGN KEY (DietPlanId)
        REFERENCES dbo.NutritionPlans(DietPlanId) ON DELETE CASCADE;
END
GO

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DietPlanAssignments_DietPlans'
           AND referenced_object_id = OBJECT_ID(N'dbo.DietPlans'))
BEGIN
    ALTER TABLE dbo.DietPlanAssignments DROP CONSTRAINT FK_DietPlanAssignments_DietPlans;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DietPlanAssignments_DietPlans')
BEGIN
    ALTER TABLE dbo.DietPlanAssignments
        ADD CONSTRAINT FK_DietPlanAssignments_DietPlans FOREIGN KEY (DietPlanId)
        REFERENCES dbo.NutritionPlans(DietPlanId) ON DELETE CASCADE;
END
GO

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_UserActiveDietPlans_DietPlans'
           AND referenced_object_id = OBJECT_ID(N'dbo.DietPlans'))
BEGIN
    ALTER TABLE dbo.UserActiveDietPlans DROP CONSTRAINT FK_UserActiveDietPlans_DietPlans;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_UserActiveDietPlans_DietPlans')
BEGIN
    ALTER TABLE dbo.UserActiveDietPlans
        ADD CONSTRAINT FK_UserActiveDietPlans_DietPlans FOREIGN KEY (DietPlanId)
        REFERENCES dbo.NutritionPlans(DietPlanId);
END
GO
