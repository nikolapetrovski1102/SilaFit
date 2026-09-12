USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Admin access to the split library: WorkoutSplits -> SplitDays -> SplitDayExercises.
--
-- Reads include the counts the console needs to warn before a destructive edit
-- (how many users have a split active, how many exercises a day carries). Writes
-- audit themselves in the same transaction and return Outcome / EntityId / Detail,
-- exactly like AdminContent.sql. Permission checks live in the API, not here.
--
-- Enum columns (Category, Level, RecommendedGoal) keep their CHECK constraints as
-- the source of truth.

CREATE OR ALTER PROCEDURE dbo.usp_Admin_Splits_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.SplitId,
           s.Name,
           s.Category,
           s.Level,
           s.DurationDays,
           s.Description,
           s.HeroImageUrl,
           s.RecommendedGoal,
           s.IsSystemDefault,
           s.SortOrder,
           s.CreatedAtUtc,
           (SELECT COUNT(*) FROM dbo.SplitDays d WHERE d.SplitId = s.SplitId) AS DayCount,
           (SELECT COUNT(*)
            FROM dbo.SplitDayExercises sde
            INNER JOIN dbo.SplitDays d ON d.SplitDayId = sde.SplitDayId
            WHERE d.SplitId = s.SplitId) AS ExerciseCount,
           (SELECT COUNT(*) FROM dbo.UserActiveSplits a WHERE a.SplitId = s.SplitId) AS ActiveUserCount
    FROM dbo.WorkoutSplits s
    ORDER BY s.SortOrder, s.Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_Split_Upsert
    @SplitId UNIQUEIDENTIFIER = NULL,
    @Name NVARCHAR(150),
    @Category NVARCHAR(50),
    @Level NVARCHAR(20),
    @DurationDays TINYINT,
    @Description NVARCHAR(500) = NULL,
    @HeroImageUrl NVARCHAR(500) = NULL,
    @RecommendedGoal NVARCHAR(20) = NULL,
    @SortOrder INT = 0,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Name = LTRIM(RTRIM(@Name));
    SET @Category = LTRIM(RTRIM(@Category));
    SET @Level = LTRIM(RTRIM(@Level));
    SET @Description = NULLIF(LTRIM(RTRIM(@Description)), N'');
    SET @HeroImageUrl = NULLIF(LTRIM(RTRIM(@HeroImageUrl)), N'');
    SET @RecommendedGoal = NULLIF(LTRIM(RTRIM(@RecommendedGoal)), N'');

    BEGIN TRANSACTION;

    IF @Name IS NULL OR @Name = N''
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId, N'A split name is required.' AS Detail;
        RETURN;
    END

    IF @DurationDays < 1 OR @DurationDays > 14
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId, N'A split lasts between 1 and 14 days.' AS Detail;
        RETURN;
    END

    DECLARE @Action NVARCHAR(30);

    IF @SplitId IS NULL
    BEGIN
        SET @SplitId = NEWID();
        SET @Action = N'Create';

        INSERT INTO dbo.WorkoutSplits
            (SplitId, Name, Category, Level, DurationDays, Description, HeroImageUrl, RecommendedGoal, IsSystemDefault, SortOrder)
        VALUES
            (@SplitId, @Name, @Category, @Level, @DurationDays, @Description, @HeroImageUrl, @RecommendedGoal, 0, @SortOrder);
    END
    ELSE
    BEGIN
        SET @Action = N'Update';

        UPDATE dbo.WorkoutSplits
        SET Name = @Name,
            Category = @Category,
            Level = @Level,
            DurationDays = @DurationDays,
            Description = @Description,
            HeroImageUrl = @HeroImageUrl,
            RecommendedGoal = @RecommendedGoal,
            SortOrder = @SortOrder
        WHERE SplitId = @SplitId;

        IF @@ROWCOUNT = 0
        BEGIN
            COMMIT TRANSACTION;
            SELECT 1 AS Outcome, @SplitId AS EntityId, N'That split no longer exists.' AS Detail;
            RETURN;
        END
    END

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, @Action, N'WorkoutSplit', CONVERT(NVARCHAR(64), @SplitId),
            @Action + N' split ''' + @Name + N''' (' + @Category + N'/' + @Level + N', '
            + CONVERT(NVARCHAR(10), @DurationDays) + N' days)', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- Deleting a split is the one delete in the console that removes a tree (days and
-- their exercise rows). Blocked outright while any user has the split active,
-- because their next workout would otherwise fail.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_Split_Delete
    @SplitId UNIQUEIDENTIFIER,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Name NVARCHAR(150);
    DECLARE @ActiveUserCount INT;
    DECLARE @DayCount INT;
    DECLARE @ExerciseCount INT;

    BEGIN TRANSACTION;

    SELECT @Name = Name FROM dbo.WorkoutSplits WHERE SplitId = @SplitId;

    IF @Name IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @SplitId AS EntityId, N'That split no longer exists.' AS Detail;
        RETURN;
    END

    SELECT @ActiveUserCount = COUNT(*) FROM dbo.UserActiveSplits WHERE SplitId = @SplitId;

    IF @ActiveUserCount > 0
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @SplitId AS EntityId,
               N'''' + @Name + N''' is active for ' + CONVERT(NVARCHAR(10), @ActiveUserCount)
               + N' user(s) and cannot be deleted.' AS Detail;
        RETURN;
    END

    -- Two scalars rather than SUM over a subquery: T-SQL rejects an aggregate of an
    -- aggregate, and the second count has to span the whole tree anyway.
    SELECT @DayCount = (SELECT COUNT(*) FROM dbo.SplitDays d WHERE d.SplitId = @SplitId),
           @ExerciseCount = (SELECT COUNT(*)
                             FROM dbo.SplitDayExercises sde
                             INNER JOIN dbo.SplitDays d ON d.SplitDayId = sde.SplitDayId
                             WHERE d.SplitId = @SplitId);

    DELETE FROM dbo.SplitDayExercises
    WHERE SplitDayId IN (SELECT SplitDayId FROM dbo.SplitDays WHERE SplitId = @SplitId);

    DELETE FROM dbo.SplitDays WHERE SplitId = @SplitId;
    DELETE FROM dbo.WorkoutSplits WHERE SplitId = @SplitId;

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Delete', N'WorkoutSplit', CONVERT(NVARCHAR(64), @SplitId),
            N'Deleted split ''' + @Name + N''' with ' + CONVERT(NVARCHAR(10), @DayCount) + N' day(s) and '
            + CONVERT(NVARCHAR(10), @ExerciseCount) + N' exercise row(s)', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_SplitDays_GetForSplit
    @SplitId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT d.SplitDayId,
           d.SplitId,
           d.DayIndex,
           d.Title,
           d.FocusLabel,
           d.EstimatedMinutes,
           d.IsRestDay,
           (SELECT COUNT(*) FROM dbo.SplitDayExercises sde WHERE sde.SplitDayId = d.SplitDayId) AS ExerciseCount
    FROM dbo.SplitDays d
    WHERE d.SplitId = @SplitId
    ORDER BY d.DayIndex;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_SplitDay_Upsert
    @SplitDayId UNIQUEIDENTIFIER = NULL,
    @SplitId UNIQUEIDENTIFIER,
    @DayIndex TINYINT,
    @Title NVARCHAR(150),
    @FocusLabel NVARCHAR(100) = NULL,
    @EstimatedMinutes SMALLINT = 45,
    @IsRestDay BIT = 0,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Title = LTRIM(RTRIM(@Title));
    SET @FocusLabel = NULLIF(LTRIM(RTRIM(@FocusLabel)), N'');

    BEGIN TRANSACTION;

    DECLARE @SplitName NVARCHAR(150);

    SELECT @SplitName = Name FROM dbo.WorkoutSplits WHERE SplitId = @SplitId;

    IF @SplitName IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @SplitId AS EntityId, N'That split no longer exists.' AS Detail;
        RETURN;
    END

    IF @Title IS NULL OR @Title = N''
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, @SplitId AS EntityId, N'A day title is required.' AS Detail;
        RETURN;
    END

    IF @DayIndex < 1 OR @DayIndex > 14
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, @SplitId AS EntityId, N'Day index must be between 1 and 14.' AS Detail;
        RETURN;
    END

    IF @EstimatedMinutes < 1 OR @EstimatedMinutes > 600
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, @SplitId AS EntityId, N'Estimated minutes must be between 1 and 600.' AS Detail;
        RETURN;
    END

    -- UQ_SplitDays_SplitDayIndex is the real guard; checked here to return a
    -- sentence instead of a duplicate-key error.
    IF EXISTS (SELECT 1
               FROM dbo.SplitDays
               WHERE SplitId = @SplitId
                 AND DayIndex = @DayIndex
                 AND (@SplitDayId IS NULL OR SplitDayId <> @SplitDayId))
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @SplitId AS EntityId,
               N'Day ' + CONVERT(NVARCHAR(10), @DayIndex) + N' already exists in ''' + @SplitName + N'''.' AS Detail;
        RETURN;
    END

    DECLARE @Action NVARCHAR(30);

    IF @SplitDayId IS NULL
    BEGIN
        SET @SplitDayId = NEWID();
        SET @Action = N'Create';

        INSERT INTO dbo.SplitDays (SplitDayId, SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes, IsRestDay)
        VALUES (@SplitDayId, @SplitId, @DayIndex, @Title, @FocusLabel, @EstimatedMinutes, @IsRestDay);
    END
    ELSE
    BEGIN
        SET @Action = N'Update';

        UPDATE dbo.SplitDays
        SET DayIndex = @DayIndex,
            Title = @Title,
            FocusLabel = @FocusLabel,
            EstimatedMinutes = @EstimatedMinutes,
            IsRestDay = @IsRestDay
        WHERE SplitDayId = @SplitDayId
          AND SplitId = @SplitId;

        IF @@ROWCOUNT = 0
        BEGIN
            COMMIT TRANSACTION;
            SELECT 1 AS Outcome, @SplitDayId AS EntityId, N'That day no longer exists on this split.' AS Detail;
            RETURN;
        END
    END

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, @Action, N'SplitDay', CONVERT(NVARCHAR(64), @SplitDayId),
            @Action + N' day ' + CONVERT(NVARCHAR(10), @DayIndex) + N' (' + @Title + N') on split ''' + @SplitName + N'''', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitDayId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_SplitDay_Delete
    @SplitDayId UNIQUEIDENTIFIER,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Title NVARCHAR(150);
    DECLARE @DayIndex TINYINT;
    DECLARE @SplitName NVARCHAR(150);
    DECLARE @ExerciseCount INT;

    BEGIN TRANSACTION;

    SELECT @Title = d.Title,
           @DayIndex = d.DayIndex,
           @SplitName = s.Name
    FROM dbo.SplitDays d
    INNER JOIN dbo.WorkoutSplits s ON s.SplitId = d.SplitId
    WHERE d.SplitDayId = @SplitDayId;

    IF @Title IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @SplitDayId AS EntityId, N'That day no longer exists.' AS Detail;
        RETURN;
    END

    SELECT @ExerciseCount = COUNT(*) FROM dbo.SplitDayExercises WHERE SplitDayId = @SplitDayId;

    -- No FK cascade here, so the exercise rows go first.
    DELETE FROM dbo.SplitDayExercises WHERE SplitDayId = @SplitDayId;
    DELETE FROM dbo.SplitDays WHERE SplitDayId = @SplitDayId;

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Delete', N'SplitDay', CONVERT(NVARCHAR(64), @SplitDayId),
            N'Deleted day ' + CONVERT(NVARCHAR(10), @DayIndex) + N' (' + @Title + N') from split ''' + @SplitName
            + N''' with ' + CONVERT(NVARCHAR(10), @ExerciseCount) + N' exercise row(s)', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitDayId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- Every prescription row of a split, with the exercise name, so the console can
-- render a day without a second lookup per exercise.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_SplitDayExercises_GetForSplit
    @SplitId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT sde.SplitDayExerciseId,
           sde.SplitDayId,
           d.DayIndex,
           sde.ExerciseId,
           e.Name AS ExerciseName,
           e.MuscleGroup,
           sde.SortOrder,
           sde.TargetSets,
           sde.TargetRepsLow,
           sde.TargetRepsHigh
    FROM dbo.SplitDayExercises sde
    INNER JOIN dbo.SplitDays d ON d.SplitDayId = sde.SplitDayId
    INNER JOIN dbo.Exercises e ON e.ExerciseId = sde.ExerciseId
    WHERE d.SplitId = @SplitId
    ORDER BY d.DayIndex, sde.SortOrder;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_SplitDayExercise_Upsert
    @SplitDayExerciseId UNIQUEIDENTIFIER = NULL,
    @SplitDayId UNIQUEIDENTIFIER,
    @ExerciseId UNIQUEIDENTIFIER,
    @SortOrder TINYINT = 0,
    @TargetSets TINYINT,
    @TargetRepsLow TINYINT,
    @TargetRepsHigh TINYINT,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @ExerciseName NVARCHAR(150);
    DECLARE @DayTitle NVARCHAR(150);

    SELECT @ExerciseName = Name FROM dbo.Exercises WHERE ExerciseId = @ExerciseId;

    IF @ExerciseName IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @ExerciseId AS EntityId, N'That exercise no longer exists.' AS Detail;
        RETURN;
    END

    SELECT @DayTitle = d.Title
    FROM dbo.SplitDays d
    WHERE d.SplitDayId = @SplitDayId;

    IF @DayTitle IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @SplitDayId AS EntityId, N'That training day no longer exists.' AS Detail;
        RETURN;
    END

    IF @TargetSets < 1 OR @TargetSets > 20
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, @SplitDayId AS EntityId, N'Target sets must be between 1 and 20.' AS Detail;
        RETURN;
    END

    IF @TargetRepsLow < 1 OR @TargetRepsHigh < 1 OR @TargetRepsLow > @TargetRepsHigh OR @TargetRepsHigh > 100
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, @SplitDayId AS EntityId,
               N'Rep range must be 1-100 with the low end no higher than the high end.' AS Detail;
        RETURN;
    END

    DECLARE @Action NVARCHAR(30);

    IF @SplitDayExerciseId IS NULL
    BEGIN
        SET @SplitDayExerciseId = NEWID();
        SET @Action = N'Create';

        INSERT INTO dbo.SplitDayExercises
            (SplitDayExerciseId, SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
        VALUES
            (@SplitDayExerciseId, @SplitDayId, @ExerciseId, @SortOrder, @TargetSets, @TargetRepsLow, @TargetRepsHigh);
    END
    ELSE
    BEGIN
        SET @Action = N'Update';

        UPDATE dbo.SplitDayExercises
        SET ExerciseId = @ExerciseId,
            SortOrder = @SortOrder,
            TargetSets = @TargetSets,
            TargetRepsLow = @TargetRepsLow,
            TargetRepsHigh = @TargetRepsHigh
        WHERE SplitDayExerciseId = @SplitDayExerciseId
          AND SplitDayId = @SplitDayId;

        IF @@ROWCOUNT = 0
        BEGIN
            COMMIT TRANSACTION;
            SELECT 1 AS Outcome, @SplitDayExerciseId AS EntityId, N'That row no longer exists on this day.' AS Detail;
            RETURN;
        END
    END

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, @Action, N'SplitDayExercise', CONVERT(NVARCHAR(64), @SplitDayExerciseId),
            @Action + N' ''' + @ExerciseName + N''' on ''' + @DayTitle + N''' ('
            + CONVERT(NVARCHAR(10), @TargetSets) + N'x' + CONVERT(NVARCHAR(10), @TargetRepsLow) + N'-'
            + CONVERT(NVARCHAR(10), @TargetRepsHigh) + N')', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitDayExerciseId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_SplitDayExercise_Delete
    @SplitDayExerciseId UNIQUEIDENTIFIER,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ExerciseName NVARCHAR(150);
    DECLARE @DayTitle NVARCHAR(150);

    BEGIN TRANSACTION;

    SELECT @ExerciseName = e.Name, @DayTitle = d.Title
    FROM dbo.SplitDayExercises sde
    INNER JOIN dbo.Exercises e ON e.ExerciseId = sde.ExerciseId
    INNER JOIN dbo.SplitDays d ON d.SplitDayId = sde.SplitDayId
    WHERE sde.SplitDayExerciseId = @SplitDayExerciseId;

    IF @ExerciseName IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @SplitDayExerciseId AS EntityId, N'That row no longer exists.' AS Detail;
        RETURN;
    END

    DELETE FROM dbo.SplitDayExercises WHERE SplitDayExerciseId = @SplitDayExerciseId;

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Delete', N'SplitDayExercise', CONVERT(NVARCHAR(64), @SplitDayExerciseId),
            N'Removed ''' + @ExerciseName + N''' from ''' + @DayTitle + N'''', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitDayExerciseId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO
