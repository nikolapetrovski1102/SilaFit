USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- DEFERRED CLEANUP - lives in database/manual-migrations/, NOT database/schema/,
-- specifically so deploy.sh's automatic schema-application loop (which applies
-- every *.sql file under database/schema/ on every run) never picks this up.
--
-- Run this manually, once, only after database/schema/025_ColumnEncryptionCutover.sql
-- has been live in production for a few days with no rollback needed. Drops
-- the "_Legacy" plaintext columns (and the CHECK constraints still attached
-- to Gender_Legacy/Goal_Legacy) for good - there is no undo after this
-- beyond restoring a pre-cleanup backup.
--
-- To run it against production:
--   docker cp database/manual-migrations/026_ColumnEncryptionCleanup.sql silen-sqlserver:/tmp/026.sql
--   docker exec -e SAPW="$(grep ^SA_PASSWORD deploy/.env | cut -d= -f2-)" silen-sqlserver /bin/bash -c \
--     '/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SAPW" -C -b -d SilenDb -i /tmp/026.sql'

IF OBJECT_ID(N'dbo.CK_UserProfiles_Gender', N'C') IS NOT NULL
    ALTER TABLE dbo.UserProfiles DROP CONSTRAINT CK_UserProfiles_Gender;
GO
IF OBJECT_ID(N'dbo.CK_UserProfiles_Goal', N'C') IS NOT NULL
    ALTER TABLE dbo.UserProfiles DROP CONSTRAINT CK_UserProfiles_Goal;
GO

IF COL_LENGTH(N'dbo.UserProfiles', N'Gender_Legacy') IS NOT NULL
BEGIN
    ALTER TABLE dbo.UserProfiles DROP COLUMN
        Gender_Legacy, AgeYears_Legacy, HeightCm_Legacy, WeightKg_Legacy, Goal_Legacy;
END
GO

IF COL_LENGTH(N'dbo.BodyweightLogs', N'WeightKg_Legacy') IS NOT NULL
BEGIN
    ALTER TABLE dbo.BodyweightLogs DROP COLUMN WeightKg_Legacy;
END
GO

IF COL_LENGTH(N'dbo.MealLogs', N'Title_Legacy') IS NOT NULL
BEGIN
    ALTER TABLE dbo.MealLogs DROP COLUMN
        Title_Legacy, CaloriesKcal_Legacy, ProteinG_Legacy, CarbsG_Legacy, FatsG_Legacy;
END
GO

IF COL_LENGTH(N'dbo.UserNutritionTargets', N'TargetCalories_Legacy') IS NOT NULL
BEGIN
    ALTER TABLE dbo.UserNutritionTargets DROP COLUMN
        TargetCalories_Legacy, TargetProteinG_Legacy, TargetCarbsG_Legacy, TargetFatsG_Legacy;
END
GO
