USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Idempotently resolves (creating if needed) today's scheduled session from
-- the user's active split rotation, then returns the session header
-- (result set 1) and its target exercises (result set 2).
CREATE OR ALTER PROCEDURE dbo.usp_WorkoutSession_GetTodayScheduled
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @SplitId UNIQUEIDENTIFIER, @ActivatedDate DATE, @DurationDays TINYINT;

    SELECT @SplitId = uas.SplitId, @ActivatedDate = CAST(uas.ActivatedAtUtc AS DATE), @DurationDays = ws.DurationDays
    FROM dbo.UserActiveSplits uas
    INNER JOIN dbo.WorkoutSplits ws ON ws.SplitId = uas.SplitId
    WHERE uas.UserId = @UserId;

    DECLARE @SplitDayId UNIQUEIDENTIFIER;

    IF @SplitId IS NOT NULL
    BEGIN
        -- 0-based position within the split's rotation. Normalised to be
        -- non-negative so a future ActivatedAtUtc (clock skew) can't index
        -- backwards - same convention as the Dart resolver and the mock seeder.
        DECLARE @CycleIndex INT =
            ((DATEDIFF(DAY, @ActivatedDate, @Today) % CAST(@DurationDays AS INT))
             + CAST(@DurationDays AS INT)) % CAST(@DurationDays AS INT);

        -- Match on the day's ordinal position, not its stored DayIndex. System
        -- and imported splits are seeded 0-based, while user-built and
        -- AI-generated splits are written 1-based (usp_UserSplitDay_Upsert
        -- enforces 1..14) - an ordinal lookup resolves both, and it also fixes
        -- the off-by-one that left a 1-based split's first day with no session
        -- on activation day and its last day unreachable.
        SELECT @SplitDayId = d.SplitDayId
        FROM (
            SELECT SplitDayId,
                   ROW_NUMBER() OVER (ORDER BY DayIndex) - 1 AS CyclePos
            FROM dbo.SplitDays
            WHERE SplitId = @SplitId
        ) d
        WHERE d.CyclePos = @CycleIndex;
    END

    DECLARE @WorkoutSessionId UNIQUEIDENTIFIER;

    SELECT @WorkoutSessionId = WorkoutSessionId
    FROM dbo.WorkoutSessions
    WHERE UserId = @UserId AND ScheduledDateUtc = @Today;

    IF @WorkoutSessionId IS NULL AND @SplitDayId IS NOT NULL
    BEGIN
        SET @WorkoutSessionId = NEWID();

        INSERT INTO dbo.WorkoutSessions (WorkoutSessionId, UserId, SplitDayId, ScheduledDateUtc, Status)
        VALUES (@WorkoutSessionId, @UserId, @SplitDayId, @Today, 'Scheduled');
    END

    SELECT
        ws.WorkoutSessionId, ws.Status, ws.ScheduledDateUtc,
        sd.SplitDayId, sd.Title, sd.FocusLabel, sd.EstimatedMinutes, sd.IsRestDay
    FROM dbo.WorkoutSessions ws
    LEFT JOIN dbo.SplitDays sd ON sd.SplitDayId = ws.SplitDayId
    WHERE ws.UserId = @UserId AND ws.ScheduledDateUtc = @Today;

    SELECT e.ExerciseId, e.Name, e.MuscleGroup, e.EquipmentType, e.DemoVideoUrl, sde.SortOrder, sde.TargetSets, sde.TargetRepsLow, sde.TargetRepsHigh
    FROM dbo.SplitDayExercises sde
    INNER JOIN dbo.Exercises e ON e.ExerciseId = sde.ExerciseId
    WHERE sde.SplitDayId = @SplitDayId
    ORDER BY sde.SortOrder;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_WorkoutSession_Complete
    @UserId UNIQUEIDENTIFIER,
    @WorkoutSessionId UNIQUEIDENTIFIER,
    @DurationMinutes SMALLINT,
    @CaloriesEstimate SMALLINT = NULL,
    @RpeScore DECIMAL(3,1) = NULL,
    @TonnageKg DECIMAL(10,2) = NULL,
    -- JSON array of {"exerciseId","setNumber","weightKg","reps"} - the set-by-set
    -- log behind real Personal Records (see `usp_WorkoutSession_GetPersonalRecords`).
    -- NULL/absent is a valid, older-client call: the session still completes,
    -- it just adds nothing to PR history.
    @SetLogsJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    UPDATE dbo.WorkoutSessions
    SET Status = 'Completed',
        CompletedAtUtc = SYSUTCDATETIME(),
        DurationMinutes = @DurationMinutes,
        CaloriesEstimate = @CaloriesEstimate,
        RpeScore = @RpeScore,
        TonnageKg = @TonnageKg
    WHERE WorkoutSessionId = @WorkoutSessionId AND UserId = @UserId;

    -- Idempotent: completing the same session twice (a retried request)
    -- replaces its set log rather than duplicating every set.
    DELETE FROM dbo.WorkoutSetLogs WHERE WorkoutSessionId = @WorkoutSessionId AND UserId = @UserId;

    IF @SetLogsJson IS NOT NULL
    BEGIN
        INSERT INTO dbo.WorkoutSetLogs (WorkoutSessionId, UserId, ExerciseId, SetNumber, WeightKg, Reps)
        SELECT @WorkoutSessionId, @UserId, j.ExerciseId, j.SetNumber, j.WeightKg, j.Reps
        FROM OPENJSON(@SetLogsJson)
        WITH (
            ExerciseId UNIQUEIDENTIFIER '$.exerciseId',
            SetNumber  TINYINT          '$.setNumber',
            WeightKg   DECIMAL(6,2)     '$.weightKg',
            Reps       SMALLINT         '$.reps'
        ) j;
    END

    COMMIT TRANSACTION;

    SELECT WorkoutSessionId, Status, CompletedAtUtc, DurationMinutes, CaloriesEstimate, RpeScore, TonnageKg
    FROM dbo.WorkoutSessions
    WHERE WorkoutSessionId = @WorkoutSessionId AND UserId = @UserId;
END
GO

-- Feeds the Progress screen's Personal Records card: the heaviest set ever
-- logged per exercise, plus whatever the heaviest set was *before* that one
-- (to show a real "+Xkg" delta) - `NULL` when the PR is the only set ever
-- logged for that exercise.
CREATE OR ALTER PROCEDURE dbo.usp_WorkoutSession_GetPersonalRecords
    @UserId UNIQUEIDENTIFIER,
    @Top INT = 5
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Ranked AS (
        SELECT
            wsl.ExerciseId,
            e.Name AS ExerciseName,
            wsl.WeightKg,
            wsl.Reps,
            wsl.CompletedAtUtc,
            ROW_NUMBER() OVER (PARTITION BY wsl.ExerciseId ORDER BY wsl.WeightKg DESC, wsl.CompletedAtUtc ASC) AS RankInExercise
        FROM dbo.WorkoutSetLogs wsl
        INNER JOIN dbo.Exercises e ON e.ExerciseId = wsl.ExerciseId
        WHERE wsl.UserId = @UserId
    ),
    Best AS (
        SELECT * FROM Ranked WHERE RankInExercise = 1
    )
    SELECT TOP (@Top)
        b.ExerciseId,
        b.ExerciseName,
        b.WeightKg,
        b.Reps,
        b.CompletedAtUtc,
        (
            SELECT MAX(prior.WeightKg)
            FROM dbo.WorkoutSetLogs prior
            WHERE prior.UserId = @UserId
              AND prior.ExerciseId = b.ExerciseId
              AND prior.CompletedAtUtc < b.CompletedAtUtc
        ) AS PreviousBestWeightKg
    FROM Best b
    ORDER BY b.CompletedAtUtc DESC;
END
GO

-- Feeds the Progress screen: aggregate totals (result set 1) plus the raw
-- per-day statuses (result set 2) the service uses to build the heatmap and
-- the rule-based narrative text.
CREATE OR ALTER PROCEDURE dbo.usp_WorkoutSession_GetRangeSummary
    @UserId UNIQUEIDENTIFIER,
    @FromDateUtc DATE,
    @ToDateUtc DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        COUNT(CASE WHEN Status = 'Completed' THEN 1 END) AS CompletedSessions,
        COUNT(*) AS ScheduledSessions,
        ISNULL(SUM(CASE WHEN Status = 'Completed' THEN TonnageKg END), 0) AS TotalTonnageKg,
        ISNULL(AVG(CASE WHEN Status = 'Completed' THEN RpeScore END), 0) AS AvgRpe
    FROM dbo.WorkoutSessions
    WHERE UserId = @UserId AND ScheduledDateUtc BETWEEN @FromDateUtc AND @ToDateUtc;

    SELECT ScheduledDateUtc, Status, TonnageKg, RpeScore
    FROM dbo.WorkoutSessions
    WHERE UserId = @UserId AND ScheduledDateUtc BETWEEN @FromDateUtc AND @ToDateUtc
    ORDER BY ScheduledDateUtc;
END
GO

-- "Still working out" heartbeat, called by the Active Workout Tracker while a
-- session is open. Records the session's start the first time it is seen and
-- refreshes LastActivityAtUtc on every ping. The notification publisher reads
-- the resulting idle gap to decide when to nudge "log your sets" - it is
-- intentionally best-effort and a no-op if there is no open session.
CREATE OR ALTER PROCEDURE dbo.usp_WorkoutSession_Heartbeat
    @UserId           UNIQUEIDENTIFIER,
    @WorkoutSessionId UNIQUEIDENTIFIER = NULL,
    @AtUtc            DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionId UNIQUEIDENTIFIER = @WorkoutSessionId;

    IF @SessionId IS NULL
    BEGIN
        SELECT TOP (1) @SessionId = WorkoutSessionId
        FROM dbo.WorkoutSessions
        WHERE UserId = @UserId
          AND CompletedAtUtc IS NULL
          AND ScheduledDateUtc = CAST(@AtUtc AS DATE)
        ORDER BY CreatedAtUtc DESC;
    END

    IF @SessionId IS NULL
    BEGIN
        RETURN;
    END

    UPDATE dbo.WorkoutSessions
    SET StartedAtUtc      = ISNULL(StartedAtUtc, @AtUtc),
        LastActivityAtUtc = @AtUtc
    WHERE WorkoutSessionId = @SessionId
      AND UserId = @UserId
      AND CompletedAtUtc IS NULL;
END
GO
