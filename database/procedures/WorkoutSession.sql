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
        -- The rotation is anchored to the Monday of the activation week, so
        -- every split's first day lands on a Monday (activating mid-week picks
        -- up at that weekday's slot). DATEDIFF(DAY, 0, ...) % 7 counts from
        -- 1900-01-01, a Monday, so it's DATEFIRST-independent - same trick as
        -- usp_Streak_GetStatus.
        DECLARE @AnchorDate DATE = DATEADD(DAY, -(DATEDIFF(DAY, 0, @ActivatedDate) % 7), @ActivatedDate);

        -- The rotation is whole weeks long so Day 1 lands on every Monday,
        -- not just the first: a 4-day split trains Mon-Thu and rests the rest
        -- of the week rather than cycling every 4 days. It spans DurationDays
        -- or the highest authored DayIndex, whichever is larger, rounded up to
        -- a multiple of 7 (so a 10-day split rotates every two weeks).
        DECLARE @MaxDayIndex INT = (SELECT MAX(DayIndex) FROM dbo.SplitDays WHERE SplitId = @SplitId);
        DECLARE @SpanDays INT = CASE WHEN ISNULL(@MaxDayIndex, 0) > @DurationDays THEN @MaxDayIndex ELSE @DurationDays END;
        DECLARE @CycleLength INT = 7 * ((CASE WHEN @SpanDays < 1 THEN 1 ELSE @SpanDays END + 6) / 7);

        -- 0-based position within the split's rotation. Normalised to be
        -- non-negative so a future ActivatedAtUtc (clock skew) can't index
        -- backwards - same convention as the Dart resolver and the mock seeder.
        DECLARE @CycleIndex INT =
            ((DATEDIFF(DAY, @AnchorDate, @Today) % @CycleLength) + @CycleLength) % @CycleLength;

        -- Match on the stored DayIndex (1-based - 001_SeedReferenceData shifts
        -- any legacy 0-based split up, and every save path enforces 1..14),
        -- not on ordinal position: a split numbered Day 1, Day 2, Day 4 rests
        -- on Day 3 instead of pulling Day 4 forward. A slot with no SplitDay
        -- leaves @SplitDayId NULL, i.e. an implicit rest day.
        SELECT @SplitDayId = SplitDayId
        FROM dbo.SplitDays
        WHERE SplitId = @SplitId AND DayIndex = @CycleIndex + 1;
    END

    DECLARE @WorkoutSessionId UNIQUEIDENTIFIER, @ExistingSplitDayId UNIQUEIDENTIFIER, @IsUnderway BIT;

    SELECT @WorkoutSessionId = WorkoutSessionId, @ExistingSplitDayId = SplitDayId,
           @IsUnderway = CASE WHEN FirstSetCompletedAtUtc IS NOT NULL OR CompletedAtUtc IS NOT NULL THEN 1 ELSE 0 END
    FROM dbo.WorkoutSessions
    WHERE UserId = @UserId AND ScheduledDateUtc = @Today;

    IF @WorkoutSessionId IS NULL AND @SplitDayId IS NOT NULL
    BEGIN
        SET @WorkoutSessionId = NEWID();

        INSERT INTO dbo.WorkoutSessions (WorkoutSessionId, UserId, SplitDayId, ScheduledDateUtc, Status)
        VALUES (@WorkoutSessionId, @UserId, @SplitDayId, @Today, 'Scheduled');
    END
    ELSE IF @WorkoutSessionId IS NOT NULL AND @IsUnderway = 0
         AND ISNULL(@ExistingSplitDayId, '00000000-0000-0000-0000-000000000000')
             <> ISNULL(@SplitDayId, '00000000-0000-0000-0000-000000000000')
    BEGIN
        -- Today's session already exists but the user switched splits (or
        -- their split day's ordinal shifted) before doing any of it, so
        -- re-point it at the newly active split's day instead of leaving it
        -- stuck on the old one. Once a set has been ticked off (or the
        -- session is completed) a switch must not yank the split out from
        -- under that workout. StartedAtUtc is deliberately not the signal:
        -- it is stamped by merely opening the tracker, so peeking at today's
        -- workout and backing out would otherwise lock the old split in.
        UPDATE dbo.WorkoutSessions
        SET SplitDayId = @SplitDayId
        WHERE WorkoutSessionId = @WorkoutSessionId;
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

-- Feeds Home's "View set history" button on a completed past day: every set
-- logged for that date's session, grouped by exercise (ordered by that
-- exercise's first logged set, so the list reads in the order the exercises
-- were actually worked, not alphabetically or by GUID) and by set number
-- within it.
CREATE OR ALTER PROCEDURE dbo.usp_WorkoutSession_GetSetLogsByDate
    @UserId UNIQUEIDENTIFIER,
    @ScheduledDateUtc DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        wsl.ExerciseId,
        e.Name AS ExerciseName,
        wsl.SetNumber,
        wsl.WeightKg,
        wsl.Reps,
        wsl.CompletedAtUtc
    FROM dbo.WorkoutSessions ws
    INNER JOIN dbo.WorkoutSetLogs wsl ON wsl.WorkoutSessionId = ws.WorkoutSessionId
    INNER JOIN dbo.Exercises e ON e.ExerciseId = wsl.ExerciseId
    WHERE ws.UserId = @UserId
      AND wsl.UserId = @UserId
      AND ws.ScheduledDateUtc = @ScheduledDateUtc
    ORDER BY MIN(wsl.CompletedAtUtc) OVER (PARTITION BY wsl.ExerciseId), wsl.SetNumber;
END
GO

-- Powers the gated "Last time" card in the Active Workout Tracker: every set
-- logged for one exercise, across the most recent sessions it was trained in
-- (most recent session first, set number ascending within each). PRO/
-- Advanced entitlement is checked in TodayService, not here.
CREATE OR ALTER PROCEDURE dbo.usp_WorkoutSetLog_GetHistoryByExercise
    @UserId     UNIQUEIDENTIFIER,
    @ExerciseId UNIQUEIDENTIFIER,
    @Top        INT = 5
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH RecentSessions AS (
        SELECT TOP (@Top) ws.WorkoutSessionId, ws.ScheduledDateUtc
        FROM dbo.WorkoutSessions ws
        WHERE ws.UserId = @UserId
          AND EXISTS (
              SELECT 1 FROM dbo.WorkoutSetLogs wsl
              WHERE wsl.WorkoutSessionId = ws.WorkoutSessionId
                AND wsl.UserId = @UserId
                AND wsl.ExerciseId = @ExerciseId
          )
        ORDER BY ws.ScheduledDateUtc DESC
    )
    SELECT
        wsl.ExerciseId,
        e.Name AS ExerciseName,
        wsl.SetNumber,
        wsl.WeightKg,
        wsl.Reps,
        wsl.CompletedAtUtc
    FROM RecentSessions rs
    INNER JOIN dbo.WorkoutSetLogs wsl ON wsl.WorkoutSessionId = rs.WorkoutSessionId
    INNER JOIN dbo.Exercises e ON e.ExerciseId = wsl.ExerciseId
    WHERE wsl.UserId = @UserId
      AND wsl.ExerciseId = @ExerciseId
    ORDER BY rs.ScheduledDateUtc DESC, wsl.SetNumber;
END
GO

-- Feeds the Progress screen's exercise picker: every exercise the user has
-- ever logged a set for, with how many sessions it was trained in and when
-- it was last trained (most recently trained first). PRO/Advanced
-- entitlement is checked in ProgressService, not here.
CREATE OR ALTER PROCEDURE dbo.usp_WorkoutSetLog_GetTrackedExercises
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        wsl.ExerciseId,
        e.Name AS ExerciseName,
        COUNT(DISTINCT wsl.WorkoutSessionId) AS SessionCount,
        MAX(wsl.CompletedAtUtc) AS LastTrainedAtUtc
    FROM dbo.WorkoutSetLogs wsl
    INNER JOIN dbo.Exercises e ON e.ExerciseId = wsl.ExerciseId
    WHERE wsl.UserId = @UserId
    GROUP BY wsl.ExerciseId, e.Name
    ORDER BY MAX(wsl.CompletedAtUtc) DESC;
END
GO

-- Feeds the Progress screen's per-exercise chart: one row per session the
-- exercise was trained in since @FromDateUtc (oldest first), reduced to the
-- heaviest set, the best Epley-estimated 1RM, and the session's total
-- volume/reps/sets for that exercise. PRO/Advanced entitlement is checked in
-- ProgressService, not here.
CREATE OR ALTER PROCEDURE dbo.usp_WorkoutSetLog_GetExerciseProgress
    @UserId      UNIQUEIDENTIFIER,
    @ExerciseId  UNIQUEIDENTIFIER,
    @FromDateUtc DATE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Sets AS (
        SELECT
            ws.WorkoutSessionId,
            ws.ScheduledDateUtc,
            wsl.WeightKg,
            wsl.Reps,
            -- Epley; a single rep already *is* the 1RM.
            CASE WHEN wsl.Reps = 1 THEN wsl.WeightKg
                 ELSE wsl.WeightKg * (1 + wsl.Reps / 30.0) END AS EstimatedOneRmKg,
            ROW_NUMBER() OVER (PARTITION BY ws.WorkoutSessionId
                               ORDER BY wsl.WeightKg DESC, wsl.Reps DESC) AS RankInSession
        FROM dbo.WorkoutSetLogs wsl
        INNER JOIN dbo.WorkoutSessions ws ON ws.WorkoutSessionId = wsl.WorkoutSessionId
        WHERE wsl.UserId = @UserId
          AND ws.UserId = @UserId
          AND wsl.ExerciseId = @ExerciseId
          AND ws.ScheduledDateUtc >= @FromDateUtc
    )
    SELECT
        s.ScheduledDateUtc,
        MAX(CASE WHEN s.RankInSession = 1 THEN s.WeightKg END) AS TopWeightKg,
        CAST(MAX(CASE WHEN s.RankInSession = 1 THEN s.Reps END) AS SMALLINT) AS TopSetReps,
        CAST(MAX(s.EstimatedOneRmKg) AS DECIMAL(8,2)) AS EstimatedOneRmKg,
        CAST(SUM(s.WeightKg * s.Reps) AS DECIMAL(12,2)) AS TotalVolumeKg,
        SUM(CAST(s.Reps AS INT)) AS TotalReps,
        COUNT(*) AS SetCount
    FROM Sets s
    GROUP BY s.WorkoutSessionId, s.ScheduledDateUtc
    ORDER BY s.ScheduledDateUtc ASC;
END
GO

-- "Still working out" heartbeat, called by the Active Workout Tracker while a
-- session is open. Records the session's start the first time it is seen and
-- refreshes LastActivityAtUtc on every ping. The notification publisher reads
-- the resulting idle gap to decide when to nudge "log your sets" - it is
-- intentionally best-effort and a no-op if there is no open session.
-- @HasCompletedSets stamps FirstSetCompletedAtUtc, which is what pins today's
-- session to its split day in usp_WorkoutSession_GetTodayScheduled.
CREATE OR ALTER PROCEDURE dbo.usp_WorkoutSession_Heartbeat
    @UserId           UNIQUEIDENTIFIER,
    @WorkoutSessionId UNIQUEIDENTIFIER = NULL,
    @AtUtc            DATETIME2(3),
    @HasCompletedSets BIT = 0
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
    SET StartedAtUtc           = ISNULL(StartedAtUtc, @AtUtc),
        LastActivityAtUtc      = @AtUtc,
        FirstSetCompletedAtUtc = CASE WHEN @HasCompletedSets = 1
                                      THEN ISNULL(FirstSetCompletedAtUtc, @AtUtc)
                                      ELSE FirstSetCompletedAtUtc END
    WHERE WorkoutSessionId = @SessionId
      AND UserId = @UserId
      AND CompletedAtUtc IS NULL;
END
GO
