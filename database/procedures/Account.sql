USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Self-service account deletion (Apple App Store Review Guideline 5.1.1(v) /
-- Google Play data-safety account-deletion requirement) and full data export.
-- See database/schema/025_ColumnEncryptionCutover.sql for which columns
-- below are AES-256-GCM ciphertext - those are decrypted at the Provider
-- layer, never in T-SQL.

-- Hard-deletes every row this user owns, then the account row itself.
-- Order matters: children before parents, though none of these FKs cascade,
-- so nothing here is strictly required by the schema - it's kept anyway so a
-- constraint added later doesn't silently break this procedure.
CREATE OR ALTER PROCEDURE dbo.usp_Account_Delete
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DELETE FROM dbo.WorkoutSetLogs WHERE UserId = @UserId;
    DELETE FROM dbo.WorkoutSessions WHERE UserId = @UserId;
    DELETE FROM dbo.UserActiveSplits WHERE UserId = @UserId;
    DELETE FROM dbo.SplitAssignments WHERE UserId = @UserId;
    DELETE FROM dbo.HydrationLogs WHERE UserId = @UserId;
    DELETE FROM dbo.BodyweightLogs WHERE UserId = @UserId;
    DELETE FROM dbo.MealLogs WHERE UserId = @UserId;
    DELETE FROM dbo.UserNutritionTargets WHERE UserId = @UserId;
    DELETE FROM dbo.UserSubscriptions WHERE UserId = @UserId;
    DELETE FROM dbo.MonthlyReviewDeliveries WHERE UserId = @UserId;
    DELETE FROM dbo.MonthlyAnalyticsReports WHERE UserId = @UserId;
    DELETE FROM dbo.WeeklyAnalyticsReports WHERE UserId = @UserId;
    DELETE FROM dbo.UserDeviceTokens WHERE UserId = @UserId;
    DELETE FROM dbo.UserNotifications WHERE UserId = @UserId;
    DELETE FROM dbo.UserNotificationStates WHERE UserId = @UserId;
    DELETE FROM dbo.UserProfiles WHERE UserId = @UserId;
    DELETE FROM dbo.UserSettings WHERE UserId = @UserId;
    DELETE FROM dbo.UserAuthIdentities WHERE UserId = @UserId;
    DELETE FROM dbo.PendingEmailVerifications WHERE ExistingUserId = @UserId;
    DELETE FROM dbo.Users WHERE UserId = @UserId;

    COMMIT TRANSACTION;
END
GO

-- Full "download my data" export: one result set per section, read in this
-- exact order by AccountProvider.ExportAsync via SqlResultSetReader. Column
-- lists mirror each feature's own Get procedure so the existing row mappers
-- (UserProfileRowMapper/SettingsRowMapper/MealPlanningRowMapper/
-- WorkoutRowMapper) can be reused as-is; only the sections with no prior
-- "get everything for this user" procedure (identities, hydration history,
-- workout-session history, set-log history) are new SELECTs.
CREATE OR ALTER PROCEDURE dbo.usp_Account_Export
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    -- 1: Account
    SELECT UserId, DeviceId, DisplayName, Email, AccountTier, CreatedAtUtc, LastLoginAtUtc, IsActive
    FROM dbo.Users
    WHERE UserId = @UserId;

    -- 2: Linked sign-in identities
    SELECT Provider, ExternalId, CreatedAtUtc
    FROM dbo.UserAuthIdentities
    WHERE UserId = @UserId
    ORDER BY CreatedAtUtc ASC;

    -- 3: Profile
    SELECT UserId, Gender, AgeYears, HeightCm, WeightKg, Goal,
           TrainingDaysPerWeek, SessionDurationMinutes, TrainingExperience, EquipmentAccess, DailyActivityLevel,
           CreatedAtUtc, UpdatedAtUtc
    FROM dbo.UserProfiles
    WHERE UserId = @UserId;

    -- 4: Settings
    SELECT UserId, TargetWaterMl, NotificationsEnabled, NotificationLocalTime, TimeZoneId,
           WeightUnit, DistanceUnit, RestTimerSoundEnabled, BarbellStandardKg, AppearanceMode,
           UpdatedAtUtc
    FROM dbo.UserSettings
    WHERE UserId = @UserId;

    -- 5: Nutrition targets
    SELECT UserId, TargetCalories, TargetProteinG, TargetCarbsG, TargetFatsG, IsManualOverride, UpdatedAtUtc
    FROM dbo.UserNutritionTargets
    WHERE UserId = @UserId;

    -- 6: Bodyweight history
    SELECT BodyweightLogId, WeightKg, LoggedAtUtc
    FROM dbo.BodyweightLogs
    WHERE UserId = @UserId
    ORDER BY LoggedAtUtc ASC;

    -- 7: Hydration history
    SELECT HydrationLogId, AmountMl, LoggedAtUtc
    FROM dbo.HydrationLogs
    WHERE UserId = @UserId
    ORDER BY LoggedAtUtc ASC;

    -- 8: Meal logs
    SELECT MealLogId, UserId, LogDateUtc, MealType, Title, CaloriesKcal, ProteinG, CarbsG, FatsG,
           Status, PlannedLocalTime, LoggedAtUtc, CreatedAtUtc
    FROM dbo.MealLogs
    WHERE UserId = @UserId
    ORDER BY LogDateUtc ASC, CreatedAtUtc ASC;

    -- 9: Workout session history
    SELECT WorkoutSessionId, ScheduledDateUtc, Status, StartedAtUtc, CompletedAtUtc,
           DurationMinutes, CaloriesEstimate, RpeScore, TonnageKg, CreatedAtUtc
    FROM dbo.WorkoutSessions
    WHERE UserId = @UserId
    ORDER BY ScheduledDateUtc ASC;

    -- 10: Workout set-log history
    SELECT WorkoutSetLogId, WorkoutSessionId, ExerciseId, SetNumber, WeightKg, Reps, CompletedAtUtc
    FROM dbo.WorkoutSetLogs
    WHERE UserId = @UserId
    ORDER BY CompletedAtUtc ASC;

    -- 11: Active subscription
    SELECT UserId, PlanId, BillingCycle, Status, StartedAtUtc, ExpiresAtUtc
    FROM dbo.UserSubscriptions
    WHERE UserId = @UserId;
END
GO
