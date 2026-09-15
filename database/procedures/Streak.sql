USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Result set 1: current unbroken streak (consecutive Completed or ActiveRest
-- days ending today, counting back, since a rest day does not break a
-- streak) + this week's compliance percentage.
-- Result set 2: Monday..Sunday of the current week with each day's session
-- status, for the "consistency strip" UI.
CREATE OR ALTER PROCEDURE dbo.usp_Streak_GetStatus
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    -- Monday of the current week. DATEDIFF(WEEK, ...) is NOT DATEFIRST-
    -- independent despite appearances (it buckets by @@DATEFIRST's week
    -- boundary, so on a server with the US-English default of 7/Sunday it
    -- rolls @Today straight into *next* week whenever @Today is a Sunday -
    -- e.g. 2026-09-13 came back as 2026-09-14). DATEDIFF(DAY, ...) has no
    -- such dependency, and since 1900-01-01 (day 0) was a Monday, the day
    -- offset mod 7 is a fixed 0=Mon..6=Sun regardless of server settings.
    DECLARE @WeekStart DATE = DATEADD(DAY, -(DATEDIFF(DAY, 0, @Today) % 7), @Today);

    ;WITH Calendar AS (
        SELECT @Today AS CalendarDate
        UNION ALL
        SELECT DATEADD(DAY, -1, CalendarDate)
        FROM Calendar
        WHERE CalendarDate > DATEADD(DAY, -59, @Today)
    ),
    DayStatus AS (
        SELECT c.CalendarDate,
               MAX(CASE WHEN ws.Status IN ('Completed', 'ActiveRest') THEN 1 ELSE 0 END) AS IsCompleted
        FROM Calendar c
        LEFT JOIN dbo.WorkoutSessions ws
               ON ws.UserId = @UserId AND ws.ScheduledDateUtc = c.CalendarDate
        GROUP BY c.CalendarDate
    ),
    Ranked AS (
        SELECT CalendarDate, IsCompleted,
               ROW_NUMBER() OVER (ORDER BY CalendarDate DESC) AS Rn
        FROM DayStatus
    ),
    FirstBreak AS (
        SELECT MIN(Rn) AS BreakRn FROM Ranked WHERE IsCompleted = 0
    )
    SELECT
        (SELECT COUNT(*) FROM Ranked WHERE Rn < ISNULL((SELECT BreakRn FROM FirstBreak), 999)) AS CurrentStreakDays,
        ISNULL((SELECT CAST(ROUND(100.0 * SUM(IsCompleted) / 7.0, 0) AS INT)
         FROM DayStatus
         WHERE CalendarDate BETWEEN @WeekStart AND DATEADD(DAY, 6, @WeekStart)), 0) AS WeeklyCompliancePercent
    OPTION (MAXRECURSION 100);

    SELECT
        w.CalendarDate AS SessionDate,
        ws.Status AS SessionStatus
    FROM (SELECT DATEADD(DAY, v.n, @WeekStart) AS CalendarDate FROM (VALUES (0),(1),(2),(3),(4),(5),(6)) AS v(n)) w
    LEFT JOIN dbo.WorkoutSessions ws
           ON ws.UserId = @UserId AND ws.ScheduledDateUtc = w.CalendarDate
    ORDER BY w.CalendarDate;
END
GO
