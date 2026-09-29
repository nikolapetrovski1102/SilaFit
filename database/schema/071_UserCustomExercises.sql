USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Exercises a user adds from the split builder / live-workout picker when the
-- catalogue doesn't have them. They live in dbo.Exercises alongside the
-- catalogue (so split days, set logs and progress keep joining one table) but
-- are private to their creator - NULL marks a shared catalogue row. Same shape
-- as dbo.FoodNutrition.CreatedByUserId (066_FoodTracking.sql): no FK to
-- dbo.Users, account deletion removes a user's rows explicitly
-- (usp_Account_Delete).
IF COL_LENGTH(N'dbo.Exercises', N'CreatedByUserId') IS NULL
BEGIN
    ALTER TABLE dbo.Exercises ADD CreatedByUserId UNIQUEIDENTIFIER NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'dbo.Exercises')
                 AND name = N'IX_Exercises_CreatedByUserId')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Exercises_CreatedByUserId
        ON dbo.Exercises (CreatedByUserId, Name)
        WHERE CreatedByUserId IS NOT NULL;
END
GO
