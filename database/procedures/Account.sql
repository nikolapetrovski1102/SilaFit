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

    -- Weekly AI plan delivery audit rows reference this user, the owned splits
    -- and the owned diet plans they delivered - all non-cascading (see
    -- 051_WeeklyAiPlans.sql) - so they must be cleared before any of those, or
    -- deletion fails on the first FK violation. This was the cause of account
    -- deletion returning the generic "Something went wrong" fallback: because
    -- the weekly batch writes a row per considered user, *any* opted-in user
    -- was blocked from deleting their account.
    DELETE FROM dbo.WeeklyAiPlanDeliveries WHERE UserId = @UserId;

    DELETE FROM dbo.WorkoutSetLogs WHERE UserId = @UserId;
    DELETE FROM dbo.WorkoutSessions WHERE UserId = @UserId;
    DELETE FROM dbo.UserActiveSplits WHERE UserId = @UserId;
    DELETE FROM dbo.SplitAssignments WHERE UserId = @UserId;
    DELETE FROM dbo.UserActiveDietPlans WHERE UserId = @UserId;
    DELETE FROM dbo.DietPlanAssignments WHERE UserId = @UserId;

    -- Owned-split tree (see 044_WorkoutSplitsUserOwnership.sql): exercises ->
    -- days -> the split rows themselves, for every split this user built via
    -- the in-app builder. None of these FKs cascade, so order matters here.
    DELETE sde
    FROM dbo.SplitDayExercises sde
    INNER JOIN dbo.SplitDays sd ON sd.SplitDayId = sde.SplitDayId
    INNER JOIN dbo.WorkoutSplits ws ON ws.SplitId = sd.SplitId
    WHERE ws.OwnerUserId = @UserId;

    DELETE sd
    FROM dbo.SplitDays sd
    INNER JOIN dbo.WorkoutSplits ws ON ws.SplitId = sd.SplitId
    WHERE ws.OwnerUserId = @UserId;

    DELETE FROM dbo.WorkoutSplits WHERE OwnerUserId = @UserId;

    -- Owned-diet-plan tree (see 045-048_DietPlan*.sql): meals -> days -> the
    -- plan rows themselves, for every plan this user built via the app.
    DELETE dpm
    FROM dbo.DietPlanMeals dpm
    INNER JOIN dbo.DietPlanDays dpd ON dpd.DietPlanDayId = dpm.DietPlanDayId
    INNER JOIN dbo.NutritionPlans dp ON dp.DietPlanId = dpd.DietPlanId
    WHERE dp.OwnerUserId = @UserId;

    DELETE dpd
    FROM dbo.DietPlanDays dpd
    INNER JOIN dbo.NutritionPlans dp ON dp.DietPlanId = dpd.DietPlanId
    WHERE dp.OwnerUserId = @UserId;

    DELETE FROM dbo.NutritionPlans WHERE OwnerUserId = @UserId;

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

-- Atomically checks and, if allowed, stamps dbo.Users.LastExportRequestedAtUtc
-- so at most one export can be requested per @CooldownDays - a "download my
-- data" export decrypts and emails a user's entire history, so it needs the
-- same per-user cooldown discipline as PendingEmailVerifications.LastSentAtUtc
-- (see 023_EmailVerification.sql), just with a much longer window. UPDLOCK +
-- HOLDLOCK on the read serializes concurrent requests from the same user so
-- two simultaneous calls can't both read "allowed" before either writes the
-- new timestamp.
CREATE OR ALTER PROCEDURE dbo.usp_Account_TryBeginExport
    @UserId UNIQUEIDENTIFIER,
    @CooldownDays INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @LastRequestedAtUtc DATETIME2(3);

    BEGIN TRANSACTION;

    SELECT @LastRequestedAtUtc = LastExportRequestedAtUtc
    FROM dbo.Users WITH (UPDLOCK, HOLDLOCK)
    WHERE UserId = @UserId;

    IF @LastRequestedAtUtc IS NOT NULL AND DATEADD(DAY, @CooldownDays, @LastRequestedAtUtc) > @Now
    BEGIN
        COMMIT TRANSACTION;
        SELECT CAST(0 AS BIT) AS Allowed, DATEADD(DAY, @CooldownDays, @LastRequestedAtUtc) AS NextAllowedAtUtc;
        RETURN;
    END

    UPDATE dbo.Users SET LastExportRequestedAtUtc = @Now WHERE UserId = @UserId;

    COMMIT TRANSACTION;

    SELECT CAST(1 AS BIT) AS Allowed, CAST(NULL AS DATETIME2(3)) AS NextAllowedAtUtc;
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
