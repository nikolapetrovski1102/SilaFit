USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Console client overview: "show me what this client actually logged".
--
-- Read-only, and gated by users.data.read / users.data.read_all in the service
-- layer (a trainer additionally has to be the one who assigned this user a split
-- or diet plan - see usp_Admin_Client_IsAssignedTo below).
--
-- Sensitive columns (UserProfiles body answers, MealLogs macros, BodyweightLogs
-- weight, UserNutritionTargets) are AES-256-GCM ciphertext; they are selected
-- as-is here and decrypted in AdminContentProvider, never in SQL - same split as
-- every other encrypted read in this codebase.
-- =============================================================================

-- Is @UserId one of the clients assigned by console operator @AdminUserId?
-- The assignment screens record who handed a split/diet plan over, which is the
-- client relationship the console lists.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_Client_IsAssignedTo
    @AdminUserId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CAST(CASE WHEN
        EXISTS (SELECT 1 FROM dbo.SplitAssignments sa
                WHERE sa.UserId = @UserId AND sa.AssignedByAdminUserId = @AdminUserId)
        OR EXISTS (SELECT 1 FROM dbo.DietPlanAssignments da
                WHERE da.UserId = @UserId AND da.AssignedByAdminUserId = @AdminUserId)
        THEN 1 ELSE 0 END AS BIT) AS IsAssigned;
END
GO

-- One client's overview over [@FromDateUtc, @ToDateUtc], as a series of result
-- sets the provider stitches into one model (the summary figures that need
-- decryption - calories, bodyweight - are computed in C#, not here).
CREATE OR ALTER PROCEDURE dbo.usp_Admin_Client_GetOverview
    @UserId UNIQUEIDENTIFIER,
    @FromDateUtc DATE,
    @ToDateUtc DATE
AS
BEGIN
    SET NOCOUNT ON;

    -- 1) Account + onboarding profile (ciphertext) + active split/diet plan +
    --    nutrition targets (ciphertext). One row, or none if the user is gone.
    SELECT
        u.UserId,
        u.DisplayName,
        u.Email,
        u.AccountTier,
        u.IsActive,
        u.CreatedAtUtc,
        u.LastLoginAtUtc,
        sub.ActivePlanCode,
        sub.BillingCycle,
        sub.SubscriptionStatus,
        sub.ExpiresAtUtc,
        pr.Gender,
        pr.AgeYears,
        pr.HeightCm,
        pr.WeightKg,
        pr.Goal,
        pr.TrainingDaysPerWeek,
        pr.SessionDurationMinutes,
        pr.TrainingExperience,
        pr.EquipmentAccess,
        pr.DailyActivityLevel,
        asp.SplitId           AS ActiveSplitId,
        asp.Name              AS ActiveSplitName,
        asp.Category          AS ActiveSplitCategory,
        asp.Level             AS ActiveSplitLevel,
        uas.ActivatedAtUtc    AS ActiveSplitActivatedAtUtc,
        adp.DietPlanId        AS ActiveDietPlanId,
        adp.Name              AS ActiveDietPlanName,
        adp.PeriodType        AS ActiveDietPlanPeriodType,
        uad.ActivatedAtUtc    AS ActiveDietPlanActivatedAtUtc,
        nt.TargetCalories,
        nt.TargetProteinG,
        nt.TargetCarbsG,
        nt.TargetFatsG
    FROM dbo.Users u
    LEFT JOIN dbo.UserProfiles pr ON pr.UserId = u.UserId
    LEFT JOIN dbo.UserActiveSplits uas ON uas.UserId = u.UserId
    LEFT JOIN dbo.WorkoutSplits asp ON asp.SplitId = uas.SplitId
    LEFT JOIN dbo.UserActiveDietPlans uad ON uad.UserId = u.UserId
    LEFT JOIN dbo.NutritionPlans adp ON adp.DietPlanId = uad.DietPlanId
    LEFT JOIN dbo.UserNutritionTargets nt ON nt.UserId = u.UserId
    OUTER APPLY
    (
        SELECT TOP (1)
               p.Code AS ActivePlanCode,
               s.BillingCycle,
               s.Status AS SubscriptionStatus,
               s.ExpiresAtUtc
        FROM dbo.UserSubscriptions s
        JOIN dbo.SubscriptionPlans p ON p.PlanId = s.PlanId
        WHERE s.UserId = u.UserId
        ORDER BY s.ExpiresAtUtc DESC
    ) sub
    WHERE u.UserId = @UserId;

    -- 2) Workout sessions in range, newest first.
    SELECT
        ws.WorkoutSessionId,
        ws.ScheduledDateUtc,
        ws.Status,
        ws.StartedAtUtc,
        ws.CompletedAtUtc,
        ws.DurationMinutes,
        ws.RpeScore,
        ws.TonnageKg,
        sd.Title AS SplitDayTitle,
        sd.FocusLabel AS SplitDayFocus,
        (SELECT COUNT(*) FROM dbo.WorkoutSetLogs l WHERE l.WorkoutSessionId = ws.WorkoutSessionId) AS SetCount
    FROM dbo.WorkoutSessions ws
    LEFT JOIN dbo.SplitDays sd ON sd.SplitDayId = ws.SplitDayId
    WHERE ws.UserId = @UserId
      AND ws.ScheduledDateUtc BETWEEN @FromDateUtc AND @ToDateUtc
    ORDER BY ws.ScheduledDateUtc DESC, ws.CreatedAtUtc DESC;

    -- 3) Logged sets in range, newest first (bounded - the console shows a
    --    recent slice, not a lifetime export).
    SELECT TOP (3000)
        l.WorkoutSetLogId,
        l.WorkoutSessionId,
        e.Name AS ExerciseName,
        e.MuscleGroup,
        l.SetNumber,
        l.WeightKg,
        l.Reps,
        l.CompletedAtUtc
    FROM dbo.WorkoutSetLogs l
    INNER JOIN dbo.Exercises e ON e.ExerciseId = l.ExerciseId
    WHERE l.UserId = @UserId
      AND CAST(l.CompletedAtUtc AS DATE) BETWEEN @FromDateUtc AND @ToDateUtc
    ORDER BY l.CompletedAtUtc DESC, l.SetNumber ASC;

    -- 4) Meals in range, newest first (macro columns are ciphertext).
    SELECT TOP (2000)
        m.MealLogId,
        m.LogDateUtc,
        m.MealType,
        m.Title,
        m.CaloriesKcal,
        m.ProteinG,
        m.CarbsG,
        m.FatsG,
        m.Status,
        m.LoggedAtUtc
    FROM dbo.MealLogs m
    WHERE m.UserId = @UserId
      AND m.LogDateUtc BETWEEN @FromDateUtc AND @ToDateUtc
    ORDER BY m.LogDateUtc DESC, m.CreatedAtUtc DESC;

    -- 5) Bodyweight in range, oldest first so the trend reads left to right
    --    (weight is ciphertext).
    SELECT TOP (1000)
        b.BodyweightLogId,
        b.LoggedAtUtc,
        b.WeightKg
    FROM dbo.BodyweightLogs b
    WHERE b.UserId = @UserId
      AND CAST(b.LoggedAtUtc AS DATE) BETWEEN @FromDateUtc AND @ToDateUtc
    ORDER BY b.LoggedAtUtc ASC;

    -- 6) Hydration as one total per day in range.
    SELECT
        CAST(h.LoggedAtUtc AS DATE) AS LogDateUtc,
        SUM(CAST(h.AmountMl AS INT)) AS TotalMl
    FROM dbo.HydrationLogs h
    WHERE h.UserId = @UserId
      AND CAST(h.LoggedAtUtc AS DATE) BETWEEN @FromDateUtc AND @ToDateUtc
    GROUP BY CAST(h.LoggedAtUtc AS DATE)
    ORDER BY LogDateUtc ASC;
END
GO
