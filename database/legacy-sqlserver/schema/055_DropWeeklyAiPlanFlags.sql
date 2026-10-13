USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Building a fresh weekly split/diet plan is now part of what an active
-- ADVANCED subscription buys, rather than something the user opts into, and
-- generated diet plans are activated as part of the ADVANCED benefit while
-- generated splits remain recommendations. Both UserSettings flags
-- added by 051_WeeklyAiPlans.sql are therefore obsolete; drop their default
-- constraints and then the columns.
IF EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_UserSettings_ReceiveWeeklyAiPlans')
BEGIN
    ALTER TABLE dbo.UserSettings DROP CONSTRAINT DF_UserSettings_ReceiveWeeklyAiPlans;
END
GO

IF EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_UserSettings_AutoActivateAiPlans')
BEGIN
    ALTER TABLE dbo.UserSettings DROP CONSTRAINT DF_UserSettings_AutoActivateAiPlans;
END
GO

IF COL_LENGTH('dbo.UserSettings', 'ReceiveWeeklyAiPlans') IS NOT NULL
BEGIN
    ALTER TABLE dbo.UserSettings DROP COLUMN ReceiveWeeklyAiPlans;
END
GO

IF COL_LENGTH('dbo.UserSettings', 'AutoActivateAiPlans') IS NOT NULL
BEGIN
    ALTER TABLE dbo.UserSettings DROP COLUMN AutoActivateAiPlans;
END
GO
