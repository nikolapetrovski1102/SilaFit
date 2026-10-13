USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Feeds AnalyticsService's monthly AI report: every real number the prompt
-- template's {{Placeholder}} tokens get substituted with, as a single flat
-- row. CurrentStreakDays/WeeklyCompliancePercent come from the same
-- dbo.ufn_Streak_GetStatus as usp_Streak_GetStatus (current-state, not
-- scoped to the requested month - a mid-month streak read is still
-- meaningful context for the AI).
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

    SELECT
        ISNULL(u.DisplayName, N'Athlete') AS DisplayName,

        ISNULL(ws.CompletedSessions, 0) AS CompletedSessions,
        ISNULL(ws.ScheduledSessions, 0) AS ScheduledSessions,
        ISNULL(ws.TotalTonnageKg, 0) AS TotalTonnageKg,
        ISNULL(ws.AvgRpe, 0) AS AvgRpe,

        st.CurrentStreakDays,
        st.WeeklyCompliancePercent,

        ISNULL(ml.LoggedMealDays, 0) AS LoggedMealDays,
        DATEDIFF(DAY, @FromDateUtc, @ToDateUtc) + 1 AS TotalDaysInRange,
        nt.TargetCalories

    FROM dbo.Users u
    CROSS APPLY dbo.ufn_Streak_GetStatus(@UserId, @Today) st
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
    WHERE u.UserId = @UserId;
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

CREATE OR ALTER PROCEDURE dbo.usp_Analytics_GetCachedWeeklyReport
    @UserId UNIQUEIDENTIFIER,
    @ReportYear SMALLINT,
    @ReportWeek TINYINT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ReportId, UserId, ReportYear, ReportWeek, SnapshotJson, ResultJson, GeneratedAtUtc
    FROM dbo.WeeklyAnalyticsReports
    WHERE UserId = @UserId AND ReportYear = @ReportYear AND ReportWeek = @ReportWeek;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Analytics_UpsertWeeklyReport
    @UserId UNIQUEIDENTIFIER,
    @ReportYear SMALLINT,
    @ReportWeek TINYINT,
    @SnapshotJson NVARCHAR(MAX),
    @ResultJson NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.WeeklyAnalyticsReports AS target
    USING (SELECT @UserId AS UserId, @ReportYear AS ReportYear, @ReportWeek AS ReportWeek) AS source
    ON target.UserId = source.UserId AND target.ReportYear = source.ReportYear AND target.ReportWeek = source.ReportWeek
    WHEN MATCHED THEN
        UPDATE SET SnapshotJson = @SnapshotJson, ResultJson = @ResultJson, GeneratedAtUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (UserId, ReportYear, ReportWeek, SnapshotJson, ResultJson)
        VALUES (@UserId, @ReportYear, @ReportWeek, @SnapshotJson, @ResultJson);

    SELECT ReportId, UserId, ReportYear, ReportWeek, SnapshotJson, ResultJson, GeneratedAtUtc
    FROM dbo.WeeklyAnalyticsReports
    WHERE UserId = @UserId AND ReportYear = @ReportYear AND ReportWeek = @ReportWeek;
END
GO

-- Recap evidence: only past missed training days and real completed sets.
-- PR includes history through report end, never future records.
CREATE OR ALTER PROCEDURE dbo.usp_Analytics_GetMonthlyExerciseHistory
    @UserId UNIQUEIDENTIFIER,
    @FromDateUtc DATE,
    @ToDateUtc DATE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT COUNT(DISTINCT ws.ScheduledDateUtc) AS MissedWorkoutDays
    FROM dbo.WorkoutSessions ws
    LEFT JOIN dbo.SplitDays sd ON sd.SplitDayId = ws.SplitDayId
    WHERE ws.UserId = @UserId
      AND ws.ScheduledDateUtc BETWEEN @FromDateUtc AND @ToDateUtc
      AND ws.ScheduledDateUtc < CAST(SYSUTCDATETIME() AS DATE)
      AND ws.Status IN ('Scheduled', 'Missed')
      AND ISNULL(sd.IsRestDay, 0) = 0;

    ;WITH RankedSets AS (
        SELECT sl.ExerciseId, sl.WorkoutSessionId, sl.WeightKg, sl.Reps,
               sl.CompletedAtUtc, ws.RpeScore,
               ROW_NUMBER() OVER (
                   PARTITION BY sl.WorkoutSessionId, sl.ExerciseId
                   ORDER BY sl.WeightKg DESC, sl.Reps DESC, sl.SetNumber, sl.WorkoutSetLogId
               ) AS SetRank
        FROM dbo.WorkoutSetLogs sl
        INNER JOIN dbo.WorkoutSessions ws ON ws.WorkoutSessionId = sl.WorkoutSessionId AND ws.UserId = sl.UserId
        WHERE sl.UserId = @UserId AND ws.Status = 'Completed'
          AND sl.CompletedAtUtc >= @FromDateUtc
          AND sl.CompletedAtUtc < DATEADD(DAY, 1, @ToDateUtc)
    )
    SELECT r.ExerciseId, e.Name AS ExerciseName, r.WeightKg, r.Reps,
           r.CompletedAtUtc, r.RpeScore, pr.RecordWeightKg
    FROM RankedSets r
    INNER JOIN dbo.Exercises e ON e.ExerciseId = r.ExerciseId
    CROSS APPLY (
        SELECT MAX(h.WeightKg) AS RecordWeightKg
        FROM dbo.WorkoutSetLogs h
        INNER JOIN dbo.WorkoutSessions hs ON hs.WorkoutSessionId = h.WorkoutSessionId AND hs.UserId = h.UserId
        WHERE h.UserId = @UserId AND h.ExerciseId = r.ExerciseId
          AND hs.Status = 'Completed'
          AND h.CompletedAtUtc < DATEADD(DAY, 1, @ToDateUtc)
    ) pr
    WHERE r.SetRank = 1
    ORDER BY e.Name, r.ExerciseId, r.CompletedAtUtc, r.WorkoutSessionId;
END
GO
