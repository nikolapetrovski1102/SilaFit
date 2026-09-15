USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Adds the MonthlyReviewUpsell category to the outbox CHECK constraint.
--
-- 032_NotificationPublish.sql only creates CK_UserNotifications_Category when
-- the table does not already exist, so an existing database kept the original
-- six categories. The publisher's monthly "unlock your review" push uses the
-- new MonthlyReviewUpsell category, and without this it would violate the
-- constraint and be audited as a delivery failure on the 1st of the month.
--
-- DROP + ADD is guarded so the script is safe to re-run (deploy.sh applies every
-- schema file on every deploy).
IF EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = N'CK_UserNotifications_Category'
      AND definition NOT LIKE N'%MonthlyReviewUpsell%'
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
                N'Motivation', N'Comeback', N'MonthlyReviewUpsell'));
END
GO
