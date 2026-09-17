USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Adds the WeeklyAiPlanReady category to the outbox CHECK constraint, same
-- precedent as 043_NotificationUpsellCategory.sql: Silen.Tools.WeeklyPlanGeneration's
-- "your AI split/diet plan is ready" push uses this category, and without it
-- the insert would violate the constraint and be audited as a delivery failure
-- every Sunday.
--
-- DROP + ADD is guarded so the script is safe to re-run (deploy.sh applies every
-- schema file on every deploy).
IF EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = N'CK_UserNotifications_Category'
      AND definition NOT LIKE N'%WeeklyAiPlanReady%'
)
BEGIN
    ALTER TABLE dbo.UserNotifications DROP CONSTRAINT CK_UserNotifications_Category;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_UserNotifications_Category')
BEGIN
    ALTER TABLE dbo.UserNotifications WITH CHECK
        ADD CONSTRAINT CK_UserNotifications_Category
            CHECK (Category IN (
                N'GymReminder', N'TrackSets', N'TrackCalories', N'MealIdea',
                N'Motivation', N'Comeback', N'MonthlyReviewUpsell', N'WeeklyAiPlanReady'));
END
GO
