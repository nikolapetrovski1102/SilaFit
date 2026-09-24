USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Current streak + this week's compliance for one user, shared by
-- usp_Streak_GetStatus (Home's streak badge) and
-- usp_Analytics_GetMonthlySnapshot so the two can't drift apart.
--
-- A day "keeps" the streak when it was either trained (Completed /
-- ActiveRest) or a rest day in the user's split. Rest days are resolved the
-- same way Home's day strip does it (resolveSplitDay in day_preview.dart):
-- from the session's own SplitDay when a session row exists, otherwise from
-- the active split's rotation - rest days usually never get a session row at
-- all (implicit rest positions past the last SplitDay) or keep the default
-- 'Scheduled' status, since nothing ever flips a real session to ActiveRest.
-- The rotation is only trusted from the split's activation date on; before
-- that the user was on some other split we no longer know about.
--
-- Today is a grace day: an unfinished today doesn't break the streak (it
-- would otherwise read 0 every morning until the workout is logged), it just
-- doesn't count yet. The break search is therefore strictly before @Today.
--
-- Looks back up to 999 days via a digits cross join rather than a recursive
-- CTE - an inline TVF can't carry its own OPTION (MAXRECURSION), and the old
-- 60-day window silently capped long streaks at 60.
CREATE OR ALTER FUNCTION dbo.ufn_Streak_GetStatus
(
    @UserId UNIQUEIDENTIFIER,
    @Today DATE
)
RETURNS TABLE
AS
RETURN
    WITH ActiveSplit AS (
        -- Same Monday-anchored, whole-weeks rotation as
        -- usp_WorkoutSession_GetTodayScheduled (@CycleLength there).
        SELECT uas.SplitId,
               CAST(uas.ActivatedAtUtc AS DATE) AS ActivatedDate,
               DATEADD(DAY, -(DATEDIFF(DAY, 0, CAST(uas.ActivatedAtUtc AS DATE)) % 7),
                       CAST(uas.ActivatedAtUtc AS DATE)) AS AnchorDate,
               7 * ((CASE WHEN ISNULL(md.MaxDayIndex, 0) > ws.DurationDays THEN md.MaxDayIndex
                          ELSE CAST(ws.DurationDays AS INT) END + 6) / 7) AS CycleLength
        FROM dbo.UserActiveSplits uas
        INNER JOIN dbo.WorkoutSplits ws ON ws.SplitId = uas.SplitId
        OUTER APPLY (SELECT MAX(CAST(sd.DayIndex AS INT)) AS MaxDayIndex
                     FROM dbo.SplitDays sd WHERE sd.SplitId = uas.SplitId) md
        WHERE uas.UserId = @UserId AND ws.DurationDays > 0
    ),
    RotationDays AS (
        -- Slot = stored DayIndex - 1, so a numbering gap (Day 1, 2, 4) rests
        -- on the missing day - see usp_WorkoutSession_GetTodayScheduled.
        SELECT sd.IsRestDay,
               CAST(sd.DayIndex AS INT) - 1 AS CyclePos
        FROM dbo.SplitDays sd
        INNER JOIN ActiveSplit a ON a.SplitId = sd.SplitId
    ),
    Digits AS (
        SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS v(n)
    ),
    Calendar AS (
        SELECT DATEADD(DAY, -(h.n * 100 + t.n * 10 + o.n), @Today) AS CalendarDate
        FROM Digits h CROSS JOIN Digits t CROSS JOIN Digits o
    ),
    DayStatus AS (
        SELECT c.CalendarDate,
               CASE
                   WHEN EXISTS (SELECT 1 FROM dbo.WorkoutSessions ws
                                WHERE ws.UserId = @UserId AND ws.ScheduledDateUtc = c.CalendarDate
                                  AND ws.Status IN ('Completed', 'ActiveRest'))
                       THEN 1
                   WHEN EXISTS (SELECT 1 FROM dbo.WorkoutSessions ws
                                INNER JOIN dbo.SplitDays sd ON sd.SplitDayId = ws.SplitDayId
                                WHERE ws.UserId = @UserId AND ws.ScheduledDateUtc = c.CalendarDate
                                  AND sd.IsRestDay = 1)
                       THEN 1
                   -- No session tied to a split day: fall back to the rotation.
                   -- A position with no non-rest SplitDay is a rest day (either
                   -- flagged IsRestDay, a gap in the numbering, or an implicit
                   -- pad past the last day).
                   WHEN NOT EXISTS (SELECT 1 FROM dbo.WorkoutSessions ws
                                    WHERE ws.UserId = @UserId AND ws.ScheduledDateUtc = c.CalendarDate
                                      AND ws.SplitDayId IS NOT NULL)
                        AND EXISTS (SELECT 1 FROM ActiveSplit a
                                    WHERE c.CalendarDate >= a.ActivatedDate
                                      AND NOT EXISTS (
                                          SELECT 1 FROM RotationDays r
                                          WHERE r.IsRestDay = 0
                                            AND r.CyclePos = ((DATEDIFF(DAY, a.AnchorDate, c.CalendarDate) % a.CycleLength)
                                                              + a.CycleLength) % a.CycleLength))
                       THEN 1
                   ELSE 0
               END AS IsKept
        FROM Calendar c
    )
    SELECT
        (SELECT COUNT(*) FROM DayStatus
         WHERE IsKept = 1
           AND CalendarDate > ISNULL((SELECT MAX(CalendarDate) FROM DayStatus
                                      WHERE IsKept = 0 AND CalendarDate < @Today),
                                     '0001-01-01')) AS CurrentStreakDays,
        -- Monday of @Today's week. DATEDIFF(WEEK, ...) is NOT DATEFIRST-
        -- independent despite appearances (it buckets by @@DATEFIRST's week
        -- boundary, so on a server with the US-English default of 7/Sunday
        -- it rolls @Today straight into *next* week whenever @Today is a
        -- Sunday - e.g. 2026-09-13 came back as 2026-09-14). DATEDIFF(DAY,
        -- ...) has no such dependency, and since 1900-01-01 (day 0) was a
        -- Monday, the day offset mod 7 is a fixed 0=Mon..6=Sun.
        ISNULL((SELECT CAST(ROUND(100.0 * SUM(IsKept) / 7.0, 0) AS INT)
                FROM DayStatus
                WHERE CalendarDate >= DATEADD(DAY, -(DATEDIFF(DAY, 0, @Today) % 7), @Today)), 0)
            AS WeeklyCompliancePercent;
GO

-- Result set 1: current streak + this week's compliance percentage (see
-- dbo.ufn_Streak_GetStatus for what counts).
-- Result set 2: Monday..Sunday of the current week with each day's session
-- status, for the "consistency strip" UI.
CREATE OR ALTER PROCEDURE dbo.usp_Streak_GetStatus
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    -- See dbo.ufn_Streak_GetStatus on why this isn't DATEDIFF(WEEK, ...).
    DECLARE @WeekStart DATE = DATEADD(DAY, -(DATEDIFF(DAY, 0, @Today) % 7), @Today);

    SELECT CurrentStreakDays, WeeklyCompliancePercent
    FROM dbo.ufn_Streak_GetStatus(@UserId, @Today);

    SELECT
        w.CalendarDate AS SessionDate,
        ws.Status AS SessionStatus
    FROM (SELECT DATEADD(DAY, v.n, @WeekStart) AS CalendarDate FROM (VALUES (0),(1),(2),(3),(4),(5),(6)) AS v(n)) w
    LEFT JOIN dbo.WorkoutSessions ws
           ON ws.UserId = @UserId AND ws.ScheduledDateUtc = w.CalendarDate
    ORDER BY w.CalendarDate;
END
GO
