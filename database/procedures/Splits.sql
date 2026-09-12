USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Splits_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    SELECT SplitId, Name, Category, Level, DurationDays, Description, HeroImageUrl, IsSystemDefault, SortOrder, RecommendedGoal
    FROM dbo.WorkoutSplits
    ORDER BY SortOrder;
END
GO

-- Result set 1: split header. Result set 2: its days. Result set 3: each
-- day's target exercises.
CREATE OR ALTER PROCEDURE dbo.usp_Splits_GetDetail
    @SplitId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT SplitId, Name, Category, Level, DurationDays, Description, HeroImageUrl, IsSystemDefault, RecommendedGoal
    FROM dbo.WorkoutSplits
    WHERE SplitId = @SplitId;

    SELECT SplitDayId, DayIndex, Title, FocusLabel, EstimatedMinutes, IsRestDay
    FROM dbo.SplitDays
    WHERE SplitId = @SplitId
    ORDER BY DayIndex;

    SELECT sd.SplitDayId, e.ExerciseId, e.Name, sde.SortOrder, sde.TargetSets, sde.TargetRepsLow, sde.TargetRepsHigh
    FROM dbo.SplitDays sd
    INNER JOIN dbo.SplitDayExercises sde ON sde.SplitDayId = sd.SplitDayId
    INNER JOIN dbo.Exercises e ON e.ExerciseId = sde.ExerciseId
    WHERE sd.SplitId = @SplitId
    ORDER BY sd.DayIndex, sde.SortOrder;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserActiveSplit_Set
    @UserId UNIQUEIDENTIFIER,
    @SplitId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.UserActiveSplits AS target
    USING (SELECT @UserId AS UserId, @SplitId AS SplitId) AS source
    ON target.UserId = source.UserId
    WHEN MATCHED THEN
        UPDATE SET SplitId = source.SplitId, ActivatedAtUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (UserId, SplitId, ActivatedAtUtc) VALUES (source.UserId, source.SplitId, SYSUTCDATETIME());

    SELECT UserId, SplitId, ActivatedAtUtc FROM dbo.UserActiveSplits WHERE UserId = @UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserActiveSplit_Get
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT uas.UserId, uas.SplitId, uas.ActivatedAtUtc, ws.Name, ws.DurationDays
    FROM dbo.UserActiveSplits uas
    INNER JOIN dbo.WorkoutSplits ws ON ws.SplitId = uas.SplitId
    WHERE uas.UserId = @UserId;
END
GO
