USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Admin (console) access to the reference content the mobile app serves:
-- exercises, meal suggestions, subscription plans and the user list.
--
-- These are deliberately separate from the runtime procedures in Exercises.sql /
-- MealPlanning.sql / Plans.sql. The app's procedures are shaped for one signed-in
-- user and return only what that user may see; these return whole tables for an
-- operator, with usage counts so the console can warn before a delete.
--
-- Writes audit themselves in the same transaction (dbo.AdminAuditLog) and return a
-- single Outcome / EntityId / Detail row - see AdminWriteOutcome in Silen.Common.
-- Permission checks are NOT here: the API decides who may call a procedure, so
-- these stay usable by the provisioning tooling without a role in scope.
--
-- Enum columns (MuscleGroup, MealType, Category...) are left to their CHECK
-- constraints as the single source of truth; the service layer rejects unknown
-- values with a friendlier message before calling.

-- =============================================================================
-- Exercises
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.usp_Admin_Exercises_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    SELECT e.ExerciseId,
           e.Name,
           e.MuscleGroup,
           e.EquipmentType,
           e.IsCompound,
           e.DemoVideoUrl,
           e.CreatedAtUtc,
           (SELECT COUNT(*) FROM dbo.SplitDayExercises sde WHERE sde.ExerciseId = e.ExerciseId) AS UsageCount
    FROM dbo.Exercises e
    ORDER BY e.MuscleGroup, e.Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_Exercise_Upsert
    @ExerciseId UNIQUEIDENTIFIER = NULL,
    @Name NVARCHAR(150),
    @MuscleGroup NVARCHAR(30),
    @EquipmentType NVARCHAR(50) = NULL,
    @IsCompound BIT,
    @DemoVideoUrl NVARCHAR(500) = NULL,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Name = LTRIM(RTRIM(@Name));
    SET @MuscleGroup = LTRIM(RTRIM(@MuscleGroup));
    SET @EquipmentType = NULLIF(LTRIM(RTRIM(@EquipmentType)), N'');
    SET @DemoVideoUrl = NULLIF(LTRIM(RTRIM(@DemoVideoUrl)), N'');

    BEGIN TRANSACTION;

    IF @Name IS NULL OR @Name = N''
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId, N'An exercise name is required.' AS Detail;
        RETURN;
    END

    DECLARE @Action NVARCHAR(30);

    IF @ExerciseId IS NULL
    BEGIN
        SET @ExerciseId = NEWID();
        SET @Action = N'Create';

        INSERT INTO dbo.Exercises (ExerciseId, Name, MuscleGroup, EquipmentType, IsCompound, DemoVideoUrl)
        VALUES (@ExerciseId, @Name, @MuscleGroup, @EquipmentType, @IsCompound, @DemoVideoUrl);
    END
    ELSE
    BEGIN
        SET @Action = N'Update';

        UPDATE dbo.Exercises
        SET Name = @Name,
            MuscleGroup = @MuscleGroup,
            EquipmentType = @EquipmentType,
            IsCompound = @IsCompound,
            DemoVideoUrl = @DemoVideoUrl
        WHERE ExerciseId = @ExerciseId;

        IF @@ROWCOUNT = 0
        BEGIN
            COMMIT TRANSACTION;
            SELECT 1 AS Outcome, @ExerciseId AS EntityId, N'That exercise no longer exists.' AS Detail;
            RETURN;
        END
    END

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, @Action, N'Exercise', CONVERT(NVARCHAR(64), @ExerciseId),
            @Action + N' exercise ''' + @Name + N''' in ' + @MuscleGroup, @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @ExerciseId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_Exercise_Delete
    @ExerciseId UNIQUEIDENTIFIER,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Name NVARCHAR(150);
    DECLARE @UsageCount INT;

    BEGIN TRANSACTION;

    SELECT @Name = Name FROM dbo.Exercises WHERE ExerciseId = @ExerciseId;

    IF @Name IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @ExerciseId AS EntityId, N'That exercise no longer exists.' AS Detail;
        RETURN;
    END

    -- Checked inside the transaction: a split-day row added a moment ago still
    -- blocks the delete, rather than surfacing as a foreign-key error.
    SELECT @UsageCount = COUNT(*) FROM dbo.SplitDayExercises WHERE ExerciseId = @ExerciseId;

    IF @UsageCount > 0
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @ExerciseId AS EntityId,
               N'Used by ' + CONVERT(NVARCHAR(10), @UsageCount) + N' split-day entry(s); remove it from those days first.' AS Detail;
        RETURN;
    END

    DELETE FROM dbo.Exercises WHERE ExerciseId = @ExerciseId;

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Delete', N'Exercise', CONVERT(NVARCHAR(64), @ExerciseId),
            N'Deleted exercise ''' + @Name + N'''', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @ExerciseId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- =============================================================================
-- Meal suggestions
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.usp_Admin_MealSuggestions_GetAll
    @SuggestedMonth TINYINT = NULL,
    @MealType NVARCHAR(20) = NULL,
    @Search NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @MealType = NULLIF(LTRIM(RTRIM(@MealType)), N'');
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');

    SELECT MealSuggestionId,
           Title,
           MealType,
           Description,
           CaloriesKcal,
           ProteinG,
           CarbsG,
           FatsG,
           SuggestedMonth,
           IsSystemDefault,
           SortOrder,
           CreatedAtUtc
    FROM dbo.MealSuggestions
    WHERE (@SuggestedMonth IS NULL OR SuggestedMonth = @SuggestedMonth)
      AND (@MealType IS NULL OR MealType = @MealType)
      AND (@Search IS NULL OR Title LIKE N'%' + @Search + N'%')
    ORDER BY SuggestedMonth, MealType, SortOrder, Title;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_MealSuggestion_Upsert
    @MealSuggestionId UNIQUEIDENTIFIER = NULL,
    @Title NVARCHAR(200),
    @MealType NVARCHAR(20),
    @Description NVARCHAR(500) = NULL,
    @CaloriesKcal SMALLINT,
    @ProteinG SMALLINT,
    @CarbsG SMALLINT,
    @FatsG SMALLINT,
    @SuggestedMonth TINYINT = NULL,
    @SortOrder INT = 0,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Title = LTRIM(RTRIM(@Title));
    SET @MealType = LTRIM(RTRIM(@MealType));
    SET @Description = NULLIF(LTRIM(RTRIM(@Description)), N'');

    BEGIN TRANSACTION;

    IF @Title IS NULL OR @Title = N''
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId, N'A title is required.' AS Detail;
        RETURN;
    END

    IF @SuggestedMonth IS NOT NULL AND (@SuggestedMonth < 1 OR @SuggestedMonth > 12)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId,
               N'Suggested month must be between 1 and 12, or left empty for a year-round suggestion.' AS Detail;
        RETURN;
    END

    IF @CaloriesKcal < 0 OR @ProteinG < 0 OR @CarbsG < 0 OR @FatsG < 0
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId,
               N'Calories and macros cannot be negative.' AS Detail;
        RETURN;
    END

    DECLARE @Action NVARCHAR(30);

    IF @MealSuggestionId IS NULL
    BEGIN
        SET @MealSuggestionId = NEWID();
        SET @Action = N'Create';

        -- Operator-authored content is not part of the shipped default set, which is
        -- what IsSystemDefault marks (the seed files insert with it set to 1).
        INSERT INTO dbo.MealSuggestions
            (MealSuggestionId, Title, MealType, Description, CaloriesKcal, ProteinG, CarbsG, FatsG,
             SuggestedMonth, IsSystemDefault, SortOrder)
        VALUES
            (@MealSuggestionId, @Title, @MealType, @Description, @CaloriesKcal, @ProteinG, @CarbsG, @FatsG,
             @SuggestedMonth, 0, @SortOrder);
    END
    ELSE
    BEGIN
        SET @Action = N'Update';

        UPDATE dbo.MealSuggestions
        SET Title = @Title,
            MealType = @MealType,
            Description = @Description,
            CaloriesKcal = @CaloriesKcal,
            ProteinG = @ProteinG,
            CarbsG = @CarbsG,
            FatsG = @FatsG,
            SuggestedMonth = @SuggestedMonth,
            SortOrder = @SortOrder
        WHERE MealSuggestionId = @MealSuggestionId;

        IF @@ROWCOUNT = 0
        BEGIN
            COMMIT TRANSACTION;
            SELECT 1 AS Outcome, @MealSuggestionId AS EntityId, N'That suggestion no longer exists.' AS Detail;
            RETURN;
        END
    END

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, @Action, N'MealSuggestion', CONVERT(NVARCHAR(64), @MealSuggestionId),
            @Action + N' meal suggestion ''' + @Title + N''' (' + @MealType + N')', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @MealSuggestionId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_MealSuggestion_Delete
    @MealSuggestionId UNIQUEIDENTIFIER,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Title NVARCHAR(200);

    BEGIN TRANSACTION;

    SELECT @Title = Title FROM dbo.MealSuggestions WHERE MealSuggestionId = @MealSuggestionId;

    IF @Title IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @MealSuggestionId AS EntityId, N'That suggestion no longer exists.' AS Detail;
        RETURN;
    END

    DELETE FROM dbo.MealSuggestions WHERE MealSuggestionId = @MealSuggestionId;

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Delete', N'MealSuggestion', CONVERT(NVARCHAR(64), @MealSuggestionId),
            N'Deleted meal suggestion ''' + @Title + N'''', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @MealSuggestionId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- =============================================================================
-- Subscription plans + their feature bullets
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.usp_Admin_Plans_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.PlanId,
           p.Code,
           p.Name,
           p.Tagline,
           p.MonthlyPrice,
           p.YearlyPrice,
           p.IsFeatured,
           p.SortOrder,
           (SELECT COUNT(*) FROM dbo.PlanFeatures f WHERE f.PlanId = p.PlanId) AS FeatureCount,
           (SELECT COUNT(*) FROM dbo.UserSubscriptions s WHERE s.PlanId = p.PlanId AND s.Status = N'Active') AS ActiveSubscriberCount
    FROM dbo.SubscriptionPlans p
    ORDER BY p.SortOrder, p.Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_Plan_Upsert
    @PlanId UNIQUEIDENTIFIER = NULL,
    @Code NVARCHAR(30),
    @Name NVARCHAR(100),
    @Tagline NVARCHAR(300) = NULL,
    @MonthlyPrice DECIMAL(9, 2),
    @YearlyPrice DECIMAL(9, 2),
    @IsFeatured BIT,
    @SortOrder INT = 0,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Code = LTRIM(RTRIM(@Code));
    SET @Name = LTRIM(RTRIM(@Name));
    SET @Tagline = NULLIF(LTRIM(RTRIM(@Tagline)), N'');

    BEGIN TRANSACTION;

    IF @Code IS NULL OR @Code = N'' OR @Name IS NULL OR @Name = N''
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId, N'A plan needs both a code and a name.' AS Detail;
        RETURN;
    END

    IF @MonthlyPrice < 0 OR @YearlyPrice < 0
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId, N'Prices cannot be negative.' AS Detail;
        RETURN;
    END

    -- Code is what the app and the pricing page key on, and it is unique in the
    -- schema; checked here so the console gets a sentence instead of a constraint
    -- violation.
    IF EXISTS (SELECT 1 FROM dbo.SubscriptionPlans WHERE Code = @Code AND (@PlanId IS NULL OR PlanId <> @PlanId))
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId,
               N'Another plan already uses the code ''' + @Code + N'''.' AS Detail;
        RETURN;
    END

    DECLARE @Action NVARCHAR(30);

    IF @PlanId IS NULL
    BEGIN
        SET @PlanId = NEWID();
        SET @Action = N'Create';

        INSERT INTO dbo.SubscriptionPlans (PlanId, Code, Name, Tagline, MonthlyPrice, YearlyPrice, IsFeatured, SortOrder)
        VALUES (@PlanId, @Code, @Name, @Tagline, @MonthlyPrice, @YearlyPrice, @IsFeatured, @SortOrder);
    END
    ELSE
    BEGIN
        SET @Action = N'Update';

        UPDATE dbo.SubscriptionPlans
        SET Code = @Code,
            Name = @Name,
            Tagline = @Tagline,
            MonthlyPrice = @MonthlyPrice,
            YearlyPrice = @YearlyPrice,
            IsFeatured = @IsFeatured,
            SortOrder = @SortOrder
        WHERE PlanId = @PlanId;

        IF @@ROWCOUNT = 0
        BEGIN
            COMMIT TRANSACTION;
            SELECT 1 AS Outcome, @PlanId AS EntityId, N'That plan no longer exists.' AS Detail;
            RETURN;
        END
    END

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, @Action, N'SubscriptionPlan', CONVERT(NVARCHAR(64), @PlanId),
            @Action + N' plan ''' + @Name + N''' (' + @Code + N')', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @PlanId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_Plan_Delete
    @PlanId UNIQUEIDENTIFIER,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Name NVARCHAR(100);
    DECLARE @SubscriberCount INT;

    BEGIN TRANSACTION;

    SELECT @Name = Name FROM dbo.SubscriptionPlans WHERE PlanId = @PlanId;

    IF @Name IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @PlanId AS EntityId, N'That plan no longer exists.' AS Detail;
        RETURN;
    END

    -- Any subscription row blocks the delete, not just active ones: those rows are
    -- the billing history and the FK is not cascading on purpose.
    SELECT @SubscriberCount = COUNT(*) FROM dbo.UserSubscriptions WHERE PlanId = @PlanId;

    IF @SubscriberCount > 0
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @PlanId AS EntityId,
               N'''' + @Name + N''' has ' + CONVERT(NVARCHAR(10), @SubscriberCount)
               + N' subscription record(s) and cannot be deleted. Rename or retire it instead.' AS Detail;
        RETURN;
    END

    DELETE FROM dbo.PlanFeatures WHERE PlanId = @PlanId;
    DELETE FROM dbo.SubscriptionPlans WHERE PlanId = @PlanId;

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Delete', N'SubscriptionPlan', CONVERT(NVARCHAR(64), @PlanId),
            N'Deleted plan ''' + @Name + N''' and its feature list', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @PlanId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_PlanFeatures_GetForPlan
    @PlanId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT PlanFeatureId, PlanId, FeatureText, SortOrder, IsHighlighted
    FROM dbo.PlanFeatures
    WHERE PlanId = @PlanId
    ORDER BY SortOrder, FeatureText;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_PlanFeature_Upsert
    @PlanFeatureId UNIQUEIDENTIFIER = NULL,
    @PlanId UNIQUEIDENTIFIER,
    @FeatureText NVARCHAR(300),
    @SortOrder TINYINT = 0,
    @IsHighlighted BIT = 0,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @FeatureText = LTRIM(RTRIM(@FeatureText));

    BEGIN TRANSACTION;

    IF @FeatureText IS NULL OR @FeatureText = N''
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId, N'A feature needs some text.' AS Detail;
        RETURN;
    END

    DECLARE @PlanName NVARCHAR(100);

    SELECT @PlanName = Name FROM dbo.SubscriptionPlans WHERE PlanId = @PlanId;

    IF @PlanName IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @PlanId AS EntityId, N'That plan no longer exists.' AS Detail;
        RETURN;
    END

    DECLARE @Action NVARCHAR(30);

    IF @PlanFeatureId IS NULL
    BEGIN
        SET @PlanFeatureId = NEWID();
        SET @Action = N'Create';

        INSERT INTO dbo.PlanFeatures (PlanFeatureId, PlanId, FeatureText, SortOrder, IsHighlighted)
        VALUES (@PlanFeatureId, @PlanId, @FeatureText, @SortOrder, @IsHighlighted);
    END
    ELSE
    BEGIN
        SET @Action = N'Update';

        UPDATE dbo.PlanFeatures
        SET FeatureText = @FeatureText,
            SortOrder = @SortOrder,
            IsHighlighted = @IsHighlighted
        WHERE PlanFeatureId = @PlanFeatureId;

        IF @@ROWCOUNT = 0
        BEGIN
            COMMIT TRANSACTION;
            SELECT 1 AS Outcome, @PlanFeatureId AS EntityId, N'That feature no longer exists.' AS Detail;
            RETURN;
        END
    END

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, @Action, N'PlanFeature', CONVERT(NVARCHAR(64), @PlanFeatureId),
            @Action + N' feature on plan ''' + @PlanName + N''': ' + @FeatureText, @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @PlanFeatureId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_PlanFeature_Delete
    @PlanFeatureId UNIQUEIDENTIFIER,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FeatureText NVARCHAR(300);
    DECLARE @PlanName NVARCHAR(100);

    BEGIN TRANSACTION;

    SELECT @FeatureText = f.FeatureText, @PlanName = p.Name
    FROM dbo.PlanFeatures f
    INNER JOIN dbo.SubscriptionPlans p ON p.PlanId = f.PlanId
    WHERE f.PlanFeatureId = @PlanFeatureId;

    IF @FeatureText IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @PlanFeatureId AS EntityId, N'That feature no longer exists.' AS Detail;
        RETURN;
    END

    DELETE FROM dbo.PlanFeatures WHERE PlanFeatureId = @PlanFeatureId;

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Delete', N'PlanFeature', CONVERT(NVARCHAR(64), @PlanFeatureId),
            N'Deleted feature from plan ''' + @PlanName + N''': ' + @FeatureText, @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @PlanFeatureId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- =============================================================================
-- Users (read-only: no operator needs to edit an app user from here)
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.usp_Admin_Users_GetAll
    @Search NVARCHAR(100) = NULL,
    @Limit INT = 200
AS
BEGIN
    SET NOCOUNT ON;

    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');
    IF @Limit IS NULL OR @Limit < 1 SET @Limit = 200;
    IF @Limit > 500 SET @Limit = 500;

    -- Account tier, join date and current subscription only - the app's own data
    -- (logs, bodyweight, nutrition) stays out of the console entirely.
    SELECT TOP (@Limit)
           u.UserId,
           u.DisplayName,
           u.Email,
           u.AccountTier,
           u.IsActive,
           u.CreatedAtUtc,
           u.LastLoginAtUtc,
           p.Code AS ActivePlanCode,
           s.BillingCycle,
           s.Status AS SubscriptionStatus,
           s.ExpiresAtUtc
    FROM dbo.Users u
    LEFT JOIN dbo.UserSubscriptions s ON s.UserId = u.UserId
    LEFT JOIN dbo.SubscriptionPlans p ON p.PlanId = s.PlanId
    WHERE (@Search IS NULL
           OR u.Email LIKE N'%' + @Search + N'%'
           OR u.DisplayName LIKE N'%' + @Search + N'%')
    ORDER BY u.CreatedAtUtc DESC;
END
GO
