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

-- @IncludeAll = 1 is an operator with content.splits.manage_all: they see the
-- whole library. Otherwise a trainer sees only what they own, plus the shipped
-- system splits (read-only reference material they can copy from).
CREATE OR ALTER PROCEDURE dbo.usp_Admin_Splits_GetAll
    @ViewerAdminUserId UNIQUEIDENTIFIER = NULL,
    @IncludeAll BIT = 1
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
           s.Visibility,
           s.OwnerAdminUserId,
           owner_admin.Username AS OwnerUsername,
           s.SortOrder,
           s.CreatedAtUtc,
           (SELECT COUNT(*) FROM dbo.SplitDays d WHERE d.SplitId = s.SplitId) AS DayCount,
           (SELECT COUNT(*)
            FROM dbo.SplitDayExercises sde
            INNER JOIN dbo.SplitDays d ON d.SplitDayId = sde.SplitDayId
            WHERE d.SplitId = s.SplitId) AS ExerciseCount,
           (SELECT COUNT(*) FROM dbo.UserActiveSplits a WHERE a.SplitId = s.SplitId) AS ActiveUserCount,
           (SELECT COUNT(*) FROM dbo.SplitAssignments asg WHERE asg.SplitId = s.SplitId) AS AssignedUserCount
    FROM dbo.WorkoutSplits s
    LEFT JOIN dbo.AdminUsers owner_admin ON owner_admin.AdminUserId = s.OwnerAdminUserId
    -- A user-built split (OwnerUserId set - see 044_WorkoutSplitsUserOwnership.sql)
    -- never surfaces in the console: it is that user's own content, managed only
    -- through the app's UserSplits endpoints, never through the admin side.
    WHERE s.OwnerUserId IS NULL
      AND (@IncludeAll = 1
           OR s.OwnerAdminUserId = @ViewerAdminUserId
           OR s.IsSystemDefault = 1)
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
    @Visibility NVARCHAR(20) = N'Public',
    @ActorCanManageAll BIT = 1,
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
    SET @Visibility = LTRIM(RTRIM(@Visibility));

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

    IF @Visibility IS NULL OR @Visibility NOT IN (N'Private', N'Public', N'Shared')
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId, N'Visibility must be Private, Public or Shared.' AS Detail;
        RETURN;
    END

    DECLARE @Action NVARCHAR(30);

    IF @SplitId IS NULL
    BEGIN
        SET @SplitId = NEWID();
        SET @Action = N'Create';

        INSERT INTO dbo.WorkoutSplits
            (SplitId, Name, Category, Level, DurationDays, Description, HeroImageUrl, RecommendedGoal,
             IsSystemDefault, SortOrder, Visibility, OwnerAdminUserId)
        VALUES
            (@SplitId, @Name, @Category, @Level, @DurationDays, @Description, @HeroImageUrl, @RecommendedGoal,
             0, @SortOrder, @Visibility, @ActorAdminUserId);
    END
    ELSE
    BEGIN
        SET @Action = N'Update';

        DECLARE @ExistingOwnerAdminUserId UNIQUEIDENTIFIER;
        DECLARE @ExistingOwnerUserId UNIQUEIDENTIFIER;

        SELECT @ExistingOwnerAdminUserId = OwnerAdminUserId,
               @ExistingOwnerUserId = OwnerUserId
        FROM dbo.WorkoutSplits
        WHERE SplitId = @SplitId;

        IF @@ROWCOUNT = 0
        BEGIN
            COMMIT TRANSACTION;
            SELECT 1 AS Outcome, @SplitId AS EntityId, N'That split no longer exists.' AS Detail;
            RETURN;
        END

        -- A split an app user built themselves (see 044_WorkoutSplitsUserOwnership.sql)
        -- is never editable from the console, regardless of manage_all - it isn't
        -- trainer/admin content at all. usp_Admin_Splits_GetAll already excludes
        -- these from the list; this is defense in depth for a direct call.
        IF @ExistingOwnerUserId IS NOT NULL
        BEGIN
            COMMIT TRANSACTION;
            SELECT 2 AS Outcome, @SplitId AS EntityId, N'This split was built by an app user and cannot be edited here.' AS Detail;
            RETURN;
        END

        -- Ownership is enforced here rather than in the API so it holds inside
        -- the same transaction as the write. A trainer may only change a split
        -- whose owner is them; manage_all operators (and tooling, which passes
        -- the default 1) may change any. System/legacy splits have a NULL owner,
        -- so they are manage_all-only too.
        IF @ActorCanManageAll = 0
           AND (@ExistingOwnerAdminUserId IS NULL OR @ExistingOwnerAdminUserId <> @ActorAdminUserId)
        BEGIN
            COMMIT TRANSACTION;
            SELECT 2 AS Outcome, @SplitId AS EntityId, N'This split belongs to another trainer.' AS Detail;
            RETURN;
        END

        UPDATE dbo.WorkoutSplits
        SET Name = @Name,
            Category = @Category,
            Level = @Level,
            DurationDays = @DurationDays,
            Description = @Description,
            HeroImageUrl = @HeroImageUrl,
            RecommendedGoal = @RecommendedGoal,
            SortOrder = @SortOrder,
            Visibility = @Visibility
        WHERE SplitId = @SplitId;
    END

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, @Action, N'WorkoutSplit', CONVERT(NVARCHAR(64), @SplitId),
            @Action + N' split ''' + @Name + N''' (' + @Category + N'/' + @Level + N', '
            + CONVERT(NVARCHAR(10), @DurationDays) + N' days, ' + @Visibility + N')', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- Deleting a split is the one delete in the console that removes a tree (days and
-- their exercise rows). Blocked outright while any user has the split active,
-- because their next workout would otherwise fail.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_Split_Delete
    @SplitId UNIQUEIDENTIFIER,
    @ActorCanManageAll BIT = 1,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Name NVARCHAR(150);
    DECLARE @OwnerAdminUserId UNIQUEIDENTIFIER;
    DECLARE @OwnerUserId UNIQUEIDENTIFIER;
    DECLARE @ActiveUserCount INT;
    DECLARE @DayCount INT;
    DECLARE @ExerciseCount INT;

    BEGIN TRANSACTION;

    SELECT @Name = Name,
           @OwnerAdminUserId = OwnerAdminUserId,
           @OwnerUserId = OwnerUserId
    FROM dbo.WorkoutSplits
    WHERE SplitId = @SplitId;

    IF @Name IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @SplitId AS EntityId, N'That split no longer exists.' AS Detail;
        RETURN;
    END

    -- Same "not console content at all" guard as the upsert - see there.
    IF @OwnerUserId IS NOT NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @SplitId AS EntityId, N'This split was built by an app user and cannot be deleted here.' AS Detail;
        RETURN;
    END

    -- Same ownership rule as the upsert: a trainer may only delete their own.
    IF @ActorCanManageAll = 0
       AND (@OwnerAdminUserId IS NULL OR @OwnerAdminUserId <> @ActorAdminUserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @SplitId AS EntityId, N'This split belongs to another trainer.' AS Detail;
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

-- =============================================================================
-- Assignment: handing a split to specific paying clients.
--
-- One SplitAssignments row means "this user may see this split", which is what
-- the app-side library filter reads. Assignment therefore works for any
-- visibility: a Private split flips to Shared the moment it is assigned (a
-- grant to a person is, by definition, sharing it with that person), while a
-- Public split stays public and simply gains another client.
--
-- @ActorCanManageAll mirrors the upsert/delete ownership rule: a trainer assigns
-- only their own splits; manage_all operators assign anything.
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.usp_Admin_SplitAssignments_GetForSplit
    @SplitId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT a.SplitId,
           a.UserId,
           u.DisplayName,
           u.Email,
           u.AccountTier,
           a.AssignedAtUtc,
           assigned_by.Username AS AssignedByUsername,
           CASE WHEN active.UserId IS NULL THEN CAST(0 AS BIT) ELSE CAST(1 AS BIT) END AS IsActive,
           subPlan.Code AS ActivePlanCode,
           sub.BillingCycle,
           sub.Status AS SubscriptionStatus
    FROM dbo.SplitAssignments a
    INNER JOIN dbo.Users u ON u.UserId = a.UserId
    LEFT JOIN dbo.AdminUsers assigned_by ON assigned_by.AdminUserId = a.AssignedByAdminUserId
    LEFT JOIN dbo.UserActiveSplits active ON active.UserId = a.UserId AND active.SplitId = a.SplitId
    -- UserSubscriptions has UserId as its primary key, so this is at most one row.
    LEFT JOIN dbo.UserSubscriptions sub ON sub.UserId = a.UserId
    LEFT JOIN dbo.SubscriptionPlans subPlan ON subPlan.PlanId = sub.PlanId
    WHERE a.SplitId = @SplitId
    ORDER BY u.DisplayName, u.Email;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_SplitAssignment_Assign
    @SplitId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER,
    @SetActive BIT = 0,
    @ActorCanManageAll BIT = 1,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @SplitName NVARCHAR(150);
    DECLARE @OwnerAdminUserId UNIQUEIDENTIFIER;
    DECLARE @Visibility NVARCHAR(20);

    SELECT @SplitName = Name,
           @OwnerAdminUserId = OwnerAdminUserId,
           @Visibility = Visibility
    FROM dbo.WorkoutSplits
    WHERE SplitId = @SplitId;

    IF @SplitName IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @SplitId AS EntityId, N'That split no longer exists.' AS Detail;
        RETURN;
    END

    IF @ActorCanManageAll = 0
       AND (@OwnerAdminUserId IS NULL OR @OwnerAdminUserId <> @ActorAdminUserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @SplitId AS EntityId, N'Only the trainer who owns this split can assign it.' AS Detail;
        RETURN;
    END

    DECLARE @ClientLabel NVARCHAR(200);

    SELECT @ClientLabel = COALESCE(NULLIF(DisplayName, N''), NULLIF(Email, N''), CONVERT(NVARCHAR(64), UserId))
    FROM dbo.Users
    WHERE UserId = @UserId;

    IF @ClientLabel IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @UserId AS EntityId, N'That user no longer exists.' AS Detail;
        RETURN;
    END

    -- Idempotent: re-assigning an already-assigned client is not an error; it
    -- only refreshes who did it and, when asked, sets it active again.
    IF EXISTS (SELECT 1 FROM dbo.SplitAssignments WHERE SplitId = @SplitId AND UserId = @UserId)
    BEGIN
        UPDATE dbo.SplitAssignments
        SET AssignedByAdminUserId = @ActorAdminUserId,
            AssignedAtUtc = SYSUTCDATETIME()
        WHERE SplitId = @SplitId AND UserId = @UserId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.SplitAssignments (SplitId, UserId, AssignedByAdminUserId)
        VALUES (@SplitId, @UserId, @ActorAdminUserId);
    END

    -- A grant to a named person makes a private split shared (with that person).
    IF @Visibility = N'Private'
    BEGIN
        UPDATE dbo.WorkoutSplits SET Visibility = N'Shared' WHERE SplitId = @SplitId;
        SET @Visibility = N'Shared';
    END

    IF @SetActive = 1
    BEGIN
        MERGE dbo.UserActiveSplits AS target
        USING (SELECT @UserId AS UserId, @SplitId AS SplitId) AS source
        ON target.UserId = source.UserId
        WHEN MATCHED THEN
            UPDATE SET SplitId = source.SplitId, ActivatedAtUtc = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN
            INSERT (UserId, SplitId, ActivatedAtUtc) VALUES (source.UserId, source.SplitId, SYSUTCDATETIME());
    END

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Assign', N'SplitAssignment', CONVERT(NVARCHAR(64), @UserId),
            N'Assigned split ''' + @SplitName + N''' (' + @Visibility + N') to ' + @ClientLabel
            + CASE WHEN @SetActive = 1 THEN N' as their active split' ELSE N'' END,
            @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_SplitAssignment_Remove
    @SplitId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER,
    @ActorCanManageAll BIT = 1,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @SplitName NVARCHAR(150);
    DECLARE @OwnerAdminUserId UNIQUEIDENTIFIER;

    SELECT @SplitName = Name,
           @OwnerAdminUserId = OwnerAdminUserId
    FROM dbo.WorkoutSplits
    WHERE SplitId = @SplitId;

    IF @SplitName IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @SplitId AS EntityId, N'That split no longer exists.' AS Detail;
        RETURN;
    END

    IF @ActorCanManageAll = 0
       AND (@OwnerAdminUserId IS NULL OR @OwnerAdminUserId <> @ActorAdminUserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @SplitId AS EntityId, N'Only the trainer who owns this split can unassign it.' AS Detail;
        RETURN;
    END

    DECLARE @WasActive BIT = 0;

    IF EXISTS (SELECT 1 FROM dbo.UserActiveSplits WHERE UserId = @UserId AND SplitId = @SplitId)
        SET @WasActive = 1;

    DELETE FROM dbo.SplitAssignments WHERE SplitId = @SplitId AND UserId = @UserId;

    IF @@ROWCOUNT = 0
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @UserId AS EntityId, N'That client was not assigned this split.' AS Detail;
        RETURN;
    END

    -- If it was their active program, clear it: the user can no longer see the
    -- split, so leaving it active would strand their Today screen on a workout
    -- they are no longer allowed to read.
    IF @WasActive = 1
    BEGIN
        DELETE FROM dbo.UserActiveSplits WHERE UserId = @UserId AND SplitId = @SplitId;
    END

    DECLARE @ClientLabel NVARCHAR(200) =
        (SELECT COALESCE(NULLIF(DisplayName, N''), NULLIF(Email, N''), CONVERT(NVARCHAR(64), UserId))
         FROM dbo.Users WHERE UserId = @UserId);

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Unassign', N'SplitAssignment', CONVERT(NVARCHAR(64), @UserId),
            N'Unassigned split ''' + @SplitName + N''' from ' + ISNULL(@ClientLabel, CONVERT(NVARCHAR(64), @UserId))
            + CASE WHEN @WasActive = 1 THEN N' (and cleared it as their active split)' ELSE N'' END,
            @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @SplitId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO
