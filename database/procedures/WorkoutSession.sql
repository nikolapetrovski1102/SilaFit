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
        DECLARE @CycleIndex INT = DATEDIFF(DAY, @ActivatedDate, @Today) % CAST(@DurationDays AS INT);

        SELECT @SplitDayId = SplitDayId
        FROM dbo.SplitDays
        WHERE SplitId = @SplitId AND DayIndex = @CycleIndex;
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
    @TonnageKg DECIMAL(10,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.WorkoutSessions
    SET Status = 'Completed',
        CompletedAtUtc = SYSUTCDATETIME(),
        DurationMinutes = @DurationMinutes,
        CaloriesEstimate = @CaloriesEstimate,
        RpeScore = @RpeScore,
        TonnageKg = @TonnageKg
    WHERE WorkoutSessionId = @WorkoutSessionId AND UserId = @UserId;

    SELECT WorkoutSessionId, Status, CompletedAtUtc, DurationMinutes, CaloriesEstimate, RpeScore, TonnageKg
    FROM dbo.WorkoutSessions
    WHERE WorkoutSessionId = @WorkoutSessionId AND UserId = @UserId;
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
