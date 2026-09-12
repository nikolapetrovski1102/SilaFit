USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Feeds AnalyticsService's monthly AI report: every real number the prompt
-- template's {{Placeholder}} tokens get substituted with, as a single flat
-- row. CurrentStreakDays/WeeklyCompliancePercent mirror usp_Streak_GetStatus
-- (current-state, not scoped to the requested month - a mid-month streak
-- read is still meaningful context for the AI).
--
-- StartWeightKg/EndWeightKg/AvgCaloriesLogged are NOT computed here anymore:
-- BodyweightLogs.WeightKg and MealLogs.CaloriesKcal are AES-256-GCM
-- ciphertext (Silen.Common.Helpers.FieldCipher) and can't be aggregated in
-- T-SQL. AnalyticsProvider fills those three fields in C# instead, via
-- IBodyweightProvider.GetInRangeAsync / IMealPlanningProvider.GetCaloriesInRangeAsync.
-- LoggedMealDays stays here since COUNT(DISTINCT LogDateUtc) never touches
-- an encrypted column.
CREATE OR ALTER PROCEDURE dbo.usp_Analytics_GetMonthlySnapshot
    @UserId UNIQUEIDENTIFIER,
    @FromDateUtc DATE,
    @ToDateUtc DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @WeekStart DATE = DATEADD(WEEK, DATEDIFF(WEEK, 0, @Today), 0);

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
        ISNULL(u.DisplayName, N'Athlete') AS DisplayName,

        ISNULL(ws.CompletedSessions, 0) AS CompletedSessions,
        ISNULL(ws.ScheduledSessions, 0) AS ScheduledSessions,
        ISNULL(ws.TotalTonnageKg, 0) AS TotalTonnageKg,
        ISNULL(ws.AvgRpe, 0) AS AvgRpe,

        (SELECT COUNT(*) FROM Ranked WHERE Rn < ISNULL((SELECT BreakRn FROM FirstBreak), 999)) AS CurrentStreakDays,
        (SELECT CAST(ROUND(100.0 * SUM(IsCompleted) / 7.0, 0) AS INT)
         FROM DayStatus
         WHERE CalendarDate BETWEEN @WeekStart AND DATEADD(DAY, 6, @WeekStart)) AS WeeklyCompliancePercent,

        ISNULL(ml.LoggedMealDays, 0) AS LoggedMealDays,
        DATEDIFF(DAY, @FromDateUtc, @ToDateUtc) + 1 AS TotalDaysInRange,
        nt.TargetCalories

    FROM dbo.Users u
    OUTER APPLY (
        SELECT
            COUNT(CASE WHEN Status = 'Completed' THEN 1 END) AS CompletedSessions,
            COUNT(*) AS ScheduledSessions,
            ISNULL(SUM(CASE WHEN Status = 'Completed' THEN TonnageKg END), 0) AS TotalTonnageKg,
            ISNULL(AVG(CASE WHEN Status = 'Completed' THEN RpeScore END), 0) AS AvgRpe
        FROM dbo.WorkoutSessions
        WHERE UserId = @UserId AND ScheduledDateUtc BETWEEN @FromDateUtc AND @ToDateUtc
    ) ws
    OUTER APPLY (
        SELECT COUNT(DISTINCT LogDateUtc) AS LoggedMealDays
        FROM dbo.MealLogs
        WHERE UserId = @UserId AND Status = 'Logged' AND LogDateUtc BETWEEN @FromDateUtc AND @ToDateUtc
    ) ml
    LEFT JOIN dbo.UserNutritionTargets nt ON nt.UserId = @UserId
    WHERE u.UserId = @UserId
    OPTION (MAXRECURSION 100);
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_AiPromptTemplate_GetActive
    @TemplateKey NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1 PromptTemplateId, TemplateKey, SystemPrompt, UserPromptTemplate, Model, IsActive, UpdatedAtUtc
    FROM dbo.AiPromptTemplates
    WHERE TemplateKey = @TemplateKey AND IsActive = 1
    ORDER BY UpdatedAtUtc DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Analytics_GetCachedReport
    @UserId UNIQUEIDENTIFIER,
    @ReportYear SMALLINT,
    @ReportMonth TINYINT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ReportId, UserId, ReportYear, ReportMonth, SnapshotJson, ResultJson, GeneratedAtUtc
    FROM dbo.MonthlyAnalyticsReports
    WHERE UserId = @UserId AND ReportYear = @ReportYear AND ReportMonth = @ReportMonth;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Analytics_UpsertReport
    @UserId UNIQUEIDENTIFIER,
    @ReportYear SMALLINT,
    @ReportMonth TINYINT,
    @SnapshotJson NVARCHAR(MAX),
    @ResultJson NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.MonthlyAnalyticsReports AS target
    USING (SELECT @UserId AS UserId, @ReportYear AS ReportYear, @ReportMonth AS ReportMonth) AS source
    ON target.UserId = source.UserId AND target.ReportYear = source.ReportYear AND target.ReportMonth = source.ReportMonth
    WHEN MATCHED THEN
        UPDATE SET SnapshotJson = @SnapshotJson, ResultJson = @ResultJson, GeneratedAtUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (UserId, ReportYear, ReportMonth, SnapshotJson, ResultJson)
        VALUES (@UserId, @ReportYear, @ReportMonth, @SnapshotJson, @ResultJson);

    SELECT ReportId, UserId, ReportYear, ReportMonth, SnapshotJson, ResultJson, GeneratedAtUtc
    FROM dbo.MonthlyAnalyticsReports
    WHERE UserId = @UserId AND ReportYear = @ReportYear AND ReportMonth = @ReportMonth;
END
GO
