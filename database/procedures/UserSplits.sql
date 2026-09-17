USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- App-facing CRUD for a user's own custom split, mirroring AdminSplits.sql's
-- shape (same Outcome/EntityId/Detail result, same validation ranges) but with
-- a single, simple ownership rule instead of the trainer/manage_all one: a
-- user may only write a split whose WorkoutSplits.OwnerUserId is themselves
-- (see 044_WorkoutSplitsUserOwnership.sql), checked inside the same
-- transaction as the write, same as the admin procs. No AdminAuditLog rows -
-- there is no user-facing audit trail in this codebase today.

CREATE OR ALTER PROCEDURE dbo.usp_UserSplits_GetOwned
    @UserId UNIQUEIDENTIFIER
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
           s.IsSystemDefault,
           s.SortOrder,
           s.RecommendedGoal,
           s.Visibility,
           s.DaysPerWeek,
           s.ProgramDurationWeeks,
           s.MinSessionMinutes,
           s.MaxSessionMinutes,
           s.EquipmentRequired,
           s.TargetGender,
           s.WorkoutTypeLabel,
           s.SourceCategoriesJson,
           s.OwnerUserId,
           s.IsAiGenerated,
           s.AiKeptAtUtc,
           ISNULL((SELECT CONVERT(INT, AVG(d.EstimatedMinutes))
                   FROM dbo.SplitDays d
                   WHERE d.SplitId = s.SplitId
                     AND d.IsRestDay = 0), 0) AS AvgSessionMinutes
    FROM dbo.WorkoutSplits s
    WHERE s.OwnerUserId = @UserId
    ORDER BY s.SortOrder, s.Name;
END
GO

-- @IsAiGenerated is only ever passed true by
-- Silen.Tools.WeeklyPlanGeneration; the manual builder always leaves it at
-- its 0 default. On UPDATE the flag is deliberately left untouched - editing
-- an AI-generated split by hand doesn't strip its AI provenance, and the
-- weekly job only ever updates a row it created itself.
CREATE OR ALTER PROCEDURE dbo.usp_UserSplit_Upsert
    @SplitId UNIQUEIDENTIFIER = NULL,
    @UserId UNIQUEIDENTIFIER,
    @Name NVARCHAR(150),
    @Category NVARCHAR(50),
    @Level NVARCHAR(20),
    @DurationDays TINYINT,
    @Description NVARCHAR(500) = NULL,
    @HeroImageUrl NVARCHAR(500) = NULL,
    @RecommendedGoal NVARCHAR(20) = NULL,
    @IsAiGenerated BIT = 0
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

    IF @SplitId IS NULL
    BEGIN
        SET @SplitId = NEWID();

        -- Always Private on create: this is the user's own content, not
        -- something to publish. Visibility is not an app-exposed concept for
        -- user-owned splits - only OwnerUserId gates who can see/edit it.
        INSERT INTO dbo.WorkoutSplits
            (SplitId, Name, Category, Level, DurationDays, Description, HeroImageUrl, RecommendedGoal,
             IsSystemDefault, SortOrder, Visibility, OwnerUserId, IsAiGenerated)
        VALUES
            (@SplitId, @Name, @Category, @Level, @DurationDays, @Description, @HeroImageUrl, @RecommendedGoal,
             0, 0, N'Private', @UserId, @IsAiGenerated);
    END
    ELSE
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.WorkoutSplits WHERE SplitId = @SplitId)
        BEGIN
            COMMIT TRANSACTION;
            SELECT 1 AS Outcome, @SplitId AS EntityId, N'That split no longer exists.' AS Detail;
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.WorkoutSplits WHERE SplitId = @SplitId AND OwnerUserId = @UserId)
        BEGIN
            COMMIT TRANSACTION;
            SELECT 2 AS Outcome, @SplitId AS EntityId, N'You can only edit splits you built yourself.' AS Detail;
            RETURN;
        END

        UPDATE dbo.WorkoutSplits
        SET Name = @Name,
            Category = @Category,
            Level = @Level,
            DurationDays = @DurationDays,
            Description = @Description,
            HeroImageUrl = @HeroImageUrl,
            RecommendedGoal = @RecommendedGoal
        WHERE SplitId = @SplitId;
    END

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- Blocked outright while any user has the split active (same guard as
-- usp_Admin_Split_Delete) - a split can only be OwnerUserId-owned by one
-- person, but that person themselves may have it active, and deleting out
-- from under their own active workout is still a footgun worth preventing.
CREATE OR ALTER PROCEDURE dbo.usp_UserSplit_Delete
    @SplitId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Name NVARCHAR(150);
    DECLARE @ActiveUserCount INT;

    BEGIN TRANSACTION;

    SELECT @Name = Name
    FROM dbo.WorkoutSplits
    WHERE SplitId = @SplitId;

    IF @Name IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @SplitId AS EntityId, N'That split no longer exists.' AS Detail;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.WorkoutSplits WHERE SplitId = @SplitId AND OwnerUserId = @UserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @SplitId AS EntityId, N'You can only delete splits you built yourself.' AS Detail;
        RETURN;
    END

    SELECT @ActiveUserCount = COUNT(*) FROM dbo.UserActiveSplits WHERE SplitId = @SplitId;

    IF @ActiveUserCount > 0
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @SplitId AS EntityId,
               N'''' + @Name + N''' is your active split - switch to another split before deleting it.' AS Detail;
        RETURN;
    END

    DELETE FROM dbo.SplitDayExercises
    WHERE SplitDayId IN (SELECT SplitDayId FROM dbo.SplitDays WHERE SplitId = @SplitId);

    DELETE FROM dbo.SplitDays WHERE SplitId = @SplitId;
    DELETE FROM dbo.WorkoutSplits WHERE SplitId = @SplitId;

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserSplitDay_Upsert
    @SplitDayId UNIQUEIDENTIFIER = NULL,
    @SplitId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER,
    @DayIndex TINYINT,
    @Title NVARCHAR(150),
    @FocusLabel NVARCHAR(100) = NULL,
    @EstimatedMinutes SMALLINT = 45,
    @IsRestDay BIT = 0
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

    IF NOT EXISTS (SELECT 1 FROM dbo.WorkoutSplits WHERE SplitId = @SplitId AND OwnerUserId = @UserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @SplitId AS EntityId, N'You can only edit splits you built yourself.' AS Detail;
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

    IF @SplitDayId IS NULL
    BEGIN
        SET @SplitDayId = NEWID();

        INSERT INTO dbo.SplitDays (SplitDayId, SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes, IsRestDay)
        VALUES (@SplitDayId, @SplitId, @DayIndex, @Title, @FocusLabel, @EstimatedMinutes, @IsRestDay);
    END
    ELSE
    BEGIN
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

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitDayId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserSplitDay_Delete
    @SplitDayId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Title NVARCHAR(150);

    BEGIN TRANSACTION;

    SELECT @Title = d.Title
    FROM dbo.SplitDays d
    INNER JOIN dbo.WorkoutSplits s ON s.SplitId = d.SplitId
    WHERE d.SplitDayId = @SplitDayId;

    IF @Title IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @SplitDayId AS EntityId, N'That day no longer exists.' AS Detail;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1
                   FROM dbo.SplitDays d
                   INNER JOIN dbo.WorkoutSplits s ON s.SplitId = d.SplitId
                   WHERE d.SplitDayId = @SplitDayId
                     AND s.OwnerUserId = @UserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @SplitDayId AS EntityId, N'You can only edit splits you built yourself.' AS Detail;
        RETURN;
    END

    DELETE FROM dbo.SplitDayExercises WHERE SplitDayId = @SplitDayId;
    DELETE FROM dbo.SplitDays WHERE SplitDayId = @SplitDayId;

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitDayId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserSplitDayExercise_Upsert
    @SplitDayExerciseId UNIQUEIDENTIFIER = NULL,
    @SplitDayId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER,
    @ExerciseId UNIQUEIDENTIFIER,
    @SortOrder TINYINT = 0,
    @TargetSets TINYINT,
    @TargetRepsLow TINYINT,
    @TargetRepsHigh TINYINT
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

    IF NOT EXISTS (SELECT 1
                   FROM dbo.SplitDays d
                   INNER JOIN dbo.WorkoutSplits s ON s.SplitId = d.SplitId
                   WHERE d.SplitDayId = @SplitDayId
                     AND s.OwnerUserId = @UserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @SplitDayId AS EntityId, N'You can only edit splits you built yourself.' AS Detail;
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

    IF @SplitDayExerciseId IS NULL
    BEGIN
        SET @SplitDayExerciseId = NEWID();

        INSERT INTO dbo.SplitDayExercises
            (SplitDayExerciseId, SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
        VALUES
            (@SplitDayExerciseId, @SplitDayId, @ExerciseId, @SortOrder, @TargetSets, @TargetRepsLow, @TargetRepsHigh);
    END
    ELSE
    BEGIN
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

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitDayExerciseId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserSplitDayExercise_Delete
    @SplitDayExerciseId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ExerciseName NVARCHAR(150);

    BEGIN TRANSACTION;

    SELECT @ExerciseName = e.Name
    FROM dbo.SplitDayExercises sde
    INNER JOIN dbo.Exercises e ON e.ExerciseId = sde.ExerciseId
    WHERE sde.SplitDayExerciseId = @SplitDayExerciseId;

    IF @ExerciseName IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @SplitDayExerciseId AS EntityId, N'That row no longer exists.' AS Detail;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1
                   FROM dbo.SplitDayExercises sde
                   INNER JOIN dbo.SplitDays d ON d.SplitDayId = sde.SplitDayId
                   INNER JOIN dbo.WorkoutSplits s ON s.SplitId = d.SplitId
                   WHERE sde.SplitDayExerciseId = @SplitDayExerciseId
                     AND s.OwnerUserId = @UserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @SplitDayExerciseId AS EntityId, N'You can only edit splits you built yourself.' AS Detail;
        RETURN;
    END

    DELETE FROM dbo.SplitDayExercises WHERE SplitDayExerciseId = @SplitDayExerciseId;

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitDayExerciseId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- Marks an AI-generated split as permanent (051_WeeklyAiPlans.sql): once
-- AiKeptAtUtc is set, Silen.Tools.WeeklyPlanGeneration's next run treats this
-- row as off-limits for overwrite-in-place and creates a fresh one instead.
-- A no-op (not an error) if the split isn't AI-generated or is already kept,
-- so the endpoint stays idempotent.
CREATE OR ALTER PROCEDURE dbo.usp_UserSplit_Keep
    @SplitId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM dbo.WorkoutSplits WHERE SplitId = @SplitId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @SplitId AS EntityId, N'That split no longer exists.' AS Detail;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.WorkoutSplits WHERE SplitId = @SplitId AND OwnerUserId = @UserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @SplitId AS EntityId, N'You can only keep splits you built yourself.' AS Detail;
        RETURN;
    END

    UPDATE dbo.WorkoutSplits
    SET AiKeptAtUtc = SYSUTCDATETIME()
    WHERE SplitId = @SplitId
      AND IsAiGenerated = 1
      AND AiKeptAtUtc IS NULL;

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO
