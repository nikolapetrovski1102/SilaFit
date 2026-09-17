USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Admin access to the diet-plan library: DietPlans -> DietPlanDays -> DietPlanMeals.
-- A 1:1 structural clone of AdminSplits.sql for the meal-planning equivalent -
-- same Outcome/EntityId/Detail write shape, same trainer-owns-their-own /
-- manage_all-owns-everything rule, same "own content only, never the app
-- user's own content" exclusion. Permission checks live in the API, not here.

-- @IncludeAll = 1 is an operator with content.diet_plans.manage_all: they see
-- the whole library. Otherwise a trainer sees only what they own, plus the
-- shipped system plans (read-only reference material they can copy from).
CREATE OR ALTER PROCEDURE dbo.usp_Admin_DietPlans_GetAll
    @ViewerAdminUserId UNIQUEIDENTIFIER = NULL,
    @IncludeAll BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    SELECT dp.DietPlanId,
           dp.Name,
           dp.Description,
           dp.HeroImageUrl,
           dp.PeriodType,
           dp.DurationDays,
           dp.IsSystemDefault,
           dp.Visibility,
           dp.OwnerAdminUserId,
           owner_admin.Username AS OwnerUsername,
           dp.SortOrder,
           dp.CreatedAtUtc,
           (SELECT COUNT(*) FROM dbo.DietPlanDays d WHERE d.DietPlanId = dp.DietPlanId) AS DayCount,
           (SELECT COUNT(*)
            FROM dbo.DietPlanMeals m
            INNER JOIN dbo.DietPlanDays d ON d.DietPlanDayId = m.DietPlanDayId
            WHERE d.DietPlanId = dp.DietPlanId) AS MealCount,
           (SELECT COUNT(*) FROM dbo.UserActiveDietPlans a WHERE a.DietPlanId = dp.DietPlanId) AS ActiveUserCount,
           (SELECT COUNT(*) FROM dbo.DietPlanAssignments asg WHERE asg.DietPlanId = dp.DietPlanId) AS AssignedUserCount
    FROM dbo.NutritionPlans dp
    LEFT JOIN dbo.AdminUsers owner_admin ON owner_admin.AdminUserId = dp.OwnerAdminUserId
    -- A user-built plan (OwnerUserId set - see 045_DietPlans.sql) never surfaces
    -- in the console: it is that user's own content, managed only through the
    -- app's UserDietPlans endpoints, never through the admin side.
    WHERE dp.OwnerUserId IS NULL
      AND (@IncludeAll = 1
           OR dp.OwnerAdminUserId = @ViewerAdminUserId
           OR dp.IsSystemDefault = 1)
    ORDER BY dp.SortOrder, dp.Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_DietPlan_Upsert
    @DietPlanId UNIQUEIDENTIFIER = NULL,
    @Name NVARCHAR(200),
    @Description NVARCHAR(1000) = NULL,
    @HeroImageUrl NVARCHAR(500) = NULL,
    @PeriodType NVARCHAR(20) = N'Weekly',
    @DurationDays TINYINT = 7,
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
    SET @Description = NULLIF(LTRIM(RTRIM(@Description)), N'');
    SET @HeroImageUrl = NULLIF(LTRIM(RTRIM(@HeroImageUrl)), N'');
    SET @PeriodType = LTRIM(RTRIM(@PeriodType));
    SET @Visibility = LTRIM(RTRIM(@Visibility));

    BEGIN TRANSACTION;

    IF @Name IS NULL OR @Name = N''
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId, N'A plan name is required.' AS Detail;
        RETURN;
    END

    IF @PeriodType IS NULL OR @PeriodType NOT IN (N'Weekly', N'Monthly')
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId, N'Period type must be Weekly or Monthly.' AS Detail;
        RETURN;
    END

    IF @DurationDays < 1 OR @DurationDays > 31
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId, N'A plan lasts between 1 and 31 days.' AS Detail;
        RETURN;
    END

    IF @Visibility IS NULL OR @Visibility NOT IN (N'Private', N'Public', N'Shared')
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId, N'Visibility must be Private, Public or Shared.' AS Detail;
        RETURN;
    END

    DECLARE @Action NVARCHAR(30);

    IF @DietPlanId IS NULL
    BEGIN
        SET @DietPlanId = NEWID();
        SET @Action = N'Create';

        INSERT INTO dbo.NutritionPlans
            (DietPlanId, Name, Description, HeroImageUrl, PeriodType, DurationDays,
             IsSystemDefault, SortOrder, Visibility, OwnerAdminUserId)
        VALUES
            (@DietPlanId, @Name, @Description, @HeroImageUrl, @PeriodType, @DurationDays,
             0, @SortOrder, @Visibility, @ActorAdminUserId);
    END
    ELSE
    BEGIN
        SET @Action = N'Update';

        DECLARE @ExistingOwnerAdminUserId UNIQUEIDENTIFIER;
        DECLARE @ExistingOwnerUserId UNIQUEIDENTIFIER;

        SELECT @ExistingOwnerAdminUserId = OwnerAdminUserId,
               @ExistingOwnerUserId = OwnerUserId
        FROM dbo.NutritionPlans
        WHERE DietPlanId = @DietPlanId;

        IF @@ROWCOUNT = 0
        BEGIN
            COMMIT TRANSACTION;
            SELECT 1 AS Outcome, @DietPlanId AS EntityId, N'That plan no longer exists.' AS Detail;
            RETURN;
        END

        -- A plan an app user built themselves is never editable from the
        -- console, regardless of manage_all - see usp_Admin_Split_Upsert's
        -- matching guard for the same rule on the workout side.
        IF @ExistingOwnerUserId IS NOT NULL
        BEGIN
            COMMIT TRANSACTION;
            SELECT 2 AS Outcome, @DietPlanId AS EntityId, N'This plan was built by an app user and cannot be edited here.' AS Detail;
            RETURN;
        END

        IF @ActorCanManageAll = 0
           AND (@ExistingOwnerAdminUserId IS NULL OR @ExistingOwnerAdminUserId <> @ActorAdminUserId)
        BEGIN
            COMMIT TRANSACTION;
            SELECT 2 AS Outcome, @DietPlanId AS EntityId, N'This plan belongs to another trainer.' AS Detail;
            RETURN;
        END

        UPDATE dbo.NutritionPlans
        SET Name = @Name,
            Description = @Description,
            HeroImageUrl = @HeroImageUrl,
            PeriodType = @PeriodType,
            DurationDays = @DurationDays,
            SortOrder = @SortOrder,
            Visibility = @Visibility
        WHERE DietPlanId = @DietPlanId;
    END

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, @Action, N'DietPlan', CONVERT(NVARCHAR(64), @DietPlanId),
            @Action + N' diet plan ''' + @Name + N''' (' + @PeriodType + N', '
            + CONVERT(NVARCHAR(10), @DurationDays) + N' days, ' + @Visibility + N')', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- Deleting a plan removes its tree (days and their meal rows). Blocked
-- outright while any user has the plan active, same guard as
-- usp_Admin_Split_Delete.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_DietPlan_Delete
    @DietPlanId UNIQUEIDENTIFIER,
    @ActorCanManageAll BIT = 1,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Name NVARCHAR(200);
    DECLARE @OwnerAdminUserId UNIQUEIDENTIFIER;
    DECLARE @OwnerUserId UNIQUEIDENTIFIER;
    DECLARE @ActiveUserCount INT;
    DECLARE @DayCount INT;
    DECLARE @MealCount INT;

    BEGIN TRANSACTION;

    SELECT @Name = Name,
           @OwnerAdminUserId = OwnerAdminUserId,
           @OwnerUserId = OwnerUserId
    FROM dbo.NutritionPlans
    WHERE DietPlanId = @DietPlanId;

    IF @Name IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @DietPlanId AS EntityId, N'That plan no longer exists.' AS Detail;
        RETURN;
    END

    IF @OwnerUserId IS NOT NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @DietPlanId AS EntityId, N'This plan was built by an app user and cannot be deleted here.' AS Detail;
        RETURN;
    END

    IF @ActorCanManageAll = 0
       AND (@OwnerAdminUserId IS NULL OR @OwnerAdminUserId <> @ActorAdminUserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @DietPlanId AS EntityId, N'This plan belongs to another trainer.' AS Detail;
        RETURN;
    END

    SELECT @ActiveUserCount = COUNT(*) FROM dbo.UserActiveDietPlans WHERE DietPlanId = @DietPlanId;

    IF @ActiveUserCount > 0
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @DietPlanId AS EntityId,
               N'''' + @Name + N''' is active for ' + CONVERT(NVARCHAR(10), @ActiveUserCount)
               + N' user(s) and cannot be deleted.' AS Detail;
        RETURN;
    END

    SELECT @DayCount = (SELECT COUNT(*) FROM dbo.DietPlanDays d WHERE d.DietPlanId = @DietPlanId),
           @MealCount = (SELECT COUNT(*)
                         FROM dbo.DietPlanMeals m
                         INNER JOIN dbo.DietPlanDays d ON d.DietPlanDayId = m.DietPlanDayId
                         WHERE d.DietPlanId = @DietPlanId);

    DELETE FROM dbo.DietPlanMeals
    WHERE DietPlanDayId IN (SELECT DietPlanDayId FROM dbo.DietPlanDays WHERE DietPlanId = @DietPlanId);

    DELETE FROM dbo.DietPlanDays WHERE DietPlanId = @DietPlanId;
    DELETE FROM dbo.NutritionPlans WHERE DietPlanId = @DietPlanId;

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Delete', N'DietPlan', CONVERT(NVARCHAR(64), @DietPlanId),
            N'Deleted diet plan ''' + @Name + N''' with ' + CONVERT(NVARCHAR(10), @DayCount) + N' day(s) and '
            + CONVERT(NVARCHAR(10), @MealCount) + N' meal row(s)', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_DietPlanDays_GetForPlan
    @DietPlanId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT d.DietPlanDayId,
           d.DietPlanId,
           d.DayIndex,
           d.Title,
           (SELECT COUNT(*) FROM dbo.DietPlanMeals m WHERE m.DietPlanDayId = d.DietPlanDayId) AS MealCount
    FROM dbo.DietPlanDays d
    WHERE d.DietPlanId = @DietPlanId
    ORDER BY d.DayIndex;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_DietPlanDay_Upsert
    @DietPlanDayId UNIQUEIDENTIFIER = NULL,
    @DietPlanId UNIQUEIDENTIFIER,
    @DayIndex TINYINT,
    @Title NVARCHAR(200) = NULL,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Title = NULLIF(LTRIM(RTRIM(@Title)), N'');

    BEGIN TRANSACTION;

    DECLARE @PlanName NVARCHAR(200);

    SELECT @PlanName = Name FROM dbo.NutritionPlans WHERE DietPlanId = @DietPlanId;

    IF @PlanName IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @DietPlanId AS EntityId, N'That plan no longer exists.' AS Detail;
        RETURN;
    END

    IF @DayIndex < 1 OR @DayIndex > 31
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, @DietPlanId AS EntityId, N'Day index must be between 1 and 31.' AS Detail;
        RETURN;
    END

    -- UQ_DietPlanDays_Plan_DayIndex is the real guard; checked here to return
    -- a sentence instead of a duplicate-key error.
    IF EXISTS (SELECT 1
               FROM dbo.DietPlanDays
               WHERE DietPlanId = @DietPlanId
                 AND DayIndex = @DayIndex
                 AND (@DietPlanDayId IS NULL OR DietPlanDayId <> @DietPlanDayId))
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @DietPlanId AS EntityId,
               N'Day ' + CONVERT(NVARCHAR(10), @DayIndex) + N' already exists in ''' + @PlanName + N'''.' AS Detail;
        RETURN;
    END

    DECLARE @Action NVARCHAR(30);

    IF @DietPlanDayId IS NULL
    BEGIN
        SET @DietPlanDayId = NEWID();
        SET @Action = N'Create';

        INSERT INTO dbo.DietPlanDays (DietPlanDayId, DietPlanId, DayIndex, Title)
        VALUES (@DietPlanDayId, @DietPlanId, @DayIndex, @Title);
    END
    ELSE
    BEGIN
        SET @Action = N'Update';

        UPDATE dbo.DietPlanDays
        SET DayIndex = @DayIndex,
            Title = @Title
        WHERE DietPlanDayId = @DietPlanDayId
          AND DietPlanId = @DietPlanId;

        IF @@ROWCOUNT = 0
        BEGIN
            COMMIT TRANSACTION;
            SELECT 1 AS Outcome, @DietPlanDayId AS EntityId, N'That day no longer exists on this plan.' AS Detail;
            RETURN;
        END
    END

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, @Action, N'DietPlanDay', CONVERT(NVARCHAR(64), @DietPlanDayId),
            @Action + N' day ' + CONVERT(NVARCHAR(10), @DayIndex) + N' on plan ''' + @PlanName + N'''', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanDayId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_DietPlanDay_Delete
    @DietPlanDayId UNIQUEIDENTIFIER,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @DayIndex TINYINT;
    DECLARE @PlanName NVARCHAR(200);
    DECLARE @MealCount INT;

    BEGIN TRANSACTION;

    SELECT @DayIndex = d.DayIndex,
           @PlanName = p.Name
    FROM dbo.DietPlanDays d
    INNER JOIN dbo.NutritionPlans p ON p.DietPlanId = d.DietPlanId
    WHERE d.DietPlanDayId = @DietPlanDayId;

    IF @PlanName IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @DietPlanDayId AS EntityId, N'That day no longer exists.' AS Detail;
        RETURN;
    END

    SELECT @MealCount = COUNT(*) FROM dbo.DietPlanMeals WHERE DietPlanDayId = @DietPlanDayId;

    DELETE FROM dbo.DietPlanMeals WHERE DietPlanDayId = @DietPlanDayId;
    DELETE FROM dbo.DietPlanDays WHERE DietPlanDayId = @DietPlanDayId;

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Delete', N'DietPlanDay', CONVERT(NVARCHAR(64), @DietPlanDayId),
            N'Deleted day ' + CONVERT(NVARCHAR(10), @DayIndex) + N' from plan ''' + @PlanName
            + N''' with ' + CONVERT(NVARCHAR(10), @MealCount) + N' meal row(s)', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanDayId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- Every meal slot of a plan, with the meal-suggestion's title/macros, so the
-- console can render a day without a second lookup per slot.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_DietPlanMeals_GetForPlan
    @DietPlanId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT m.DietPlanMealId,
           m.DietPlanDayId,
           d.DayIndex,
           m.MealType,
           m.MealSuggestionId,
           ms.Title AS MealSuggestionTitle,
           ms.CaloriesKcal,
           ms.ProteinG,
           ms.CarbsG,
           ms.FatsG,
           m.SortOrder
    FROM dbo.DietPlanMeals m
    INNER JOIN dbo.DietPlanDays d ON d.DietPlanDayId = m.DietPlanDayId
    INNER JOIN dbo.MealSuggestions ms ON ms.MealSuggestionId = m.MealSuggestionId
    WHERE d.DietPlanId = @DietPlanId
    ORDER BY d.DayIndex, m.SortOrder;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_DietPlanMeal_Upsert
    @DietPlanMealId UNIQUEIDENTIFIER = NULL,
    @DietPlanDayId UNIQUEIDENTIFIER,
    @MealType NVARCHAR(20),
    @MealSuggestionId UNIQUEIDENTIFIER,
    @SortOrder INT = 0,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @MealType = LTRIM(RTRIM(@MealType));

    BEGIN TRANSACTION;

    DECLARE @DayTitle NVARCHAR(200);
    DECLARE @DayIndex TINYINT;

    SELECT @DayTitle = ISNULL(Title, N'Day ' + CONVERT(NVARCHAR(10), DayIndex)), @DayIndex = DayIndex
    FROM dbo.DietPlanDays
    WHERE DietPlanDayId = @DietPlanDayId;

    IF @DayIndex IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @DietPlanDayId AS EntityId, N'That plan day no longer exists.' AS Detail;
        RETURN;
    END

    IF @MealType IS NULL OR @MealType NOT IN (N'Breakfast', N'Lunch', N'Dinner', N'Snack')
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, @DietPlanDayId AS EntityId, N'Meal type must be Breakfast, Lunch, Dinner or Snack.' AS Detail;
        RETURN;
    END

    DECLARE @MealSuggestionTitle NVARCHAR(200);

    SELECT @MealSuggestionTitle = Title FROM dbo.MealSuggestions WHERE MealSuggestionId = @MealSuggestionId;

    IF @MealSuggestionTitle IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @MealSuggestionId AS EntityId, N'That meal suggestion no longer exists.' AS Detail;
        RETURN;
    END

    DECLARE @Action NVARCHAR(30);

    IF @DietPlanMealId IS NULL
    BEGIN
        SET @DietPlanMealId = NEWID();
        SET @Action = N'Create';

        INSERT INTO dbo.DietPlanMeals (DietPlanMealId, DietPlanDayId, MealType, MealSuggestionId, SortOrder)
        VALUES (@DietPlanMealId, @DietPlanDayId, @MealType, @MealSuggestionId, @SortOrder);
    END
    ELSE
    BEGIN
        SET @Action = N'Update';

        UPDATE dbo.DietPlanMeals
        SET MealType = @MealType,
            MealSuggestionId = @MealSuggestionId,
            SortOrder = @SortOrder
        WHERE DietPlanMealId = @DietPlanMealId
          AND DietPlanDayId = @DietPlanDayId;

        IF @@ROWCOUNT = 0
        BEGIN
            COMMIT TRANSACTION;
            SELECT 1 AS Outcome, @DietPlanMealId AS EntityId, N'That meal slot no longer exists on this day.' AS Detail;
            RETURN;
        END
    END

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, @Action, N'DietPlanMeal', CONVERT(NVARCHAR(64), @DietPlanMealId),
            @Action + N' ' + @MealType + N' ''' + @MealSuggestionTitle + N''' on ''' + @DayTitle + N'''', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanMealId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_DietPlanMeal_Delete
    @DietPlanMealId UNIQUEIDENTIFIER,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @MealSuggestionTitle NVARCHAR(200);
    DECLARE @DayTitle NVARCHAR(200);

    BEGIN TRANSACTION;

    SELECT @MealSuggestionTitle = ms.Title,
           @DayTitle = ISNULL(d.Title, N'Day ' + CONVERT(NVARCHAR(10), d.DayIndex))
    FROM dbo.DietPlanMeals m
    INNER JOIN dbo.MealSuggestions ms ON ms.MealSuggestionId = m.MealSuggestionId
    INNER JOIN dbo.DietPlanDays d ON d.DietPlanDayId = m.DietPlanDayId
    WHERE m.DietPlanMealId = @DietPlanMealId;

    IF @MealSuggestionTitle IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @DietPlanMealId AS EntityId, N'That meal slot no longer exists.' AS Detail;
        RETURN;
    END

    DELETE FROM dbo.DietPlanMeals WHERE DietPlanMealId = @DietPlanMealId;

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Delete', N'DietPlanMeal', CONVERT(NVARCHAR(64), @DietPlanMealId),
            N'Removed ''' + @MealSuggestionTitle + N''' from ''' + @DayTitle + N'''', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanMealId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- =============================================================================
-- Assignment: handing a diet plan to specific paying clients. Mirrors
-- usp_Admin_SplitAssignment_* exactly, including the Private->Shared-on-assign
-- flip and the @SetActive MERGE into UserActiveDietPlans.
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.usp_Admin_DietPlanAssignments_GetForPlan
    @DietPlanId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT a.DietPlanId,
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
    FROM dbo.DietPlanAssignments a
    INNER JOIN dbo.Users u ON u.UserId = a.UserId
    LEFT JOIN dbo.AdminUsers assigned_by ON assigned_by.AdminUserId = a.AssignedByAdminUserId
    LEFT JOIN dbo.UserActiveDietPlans active ON active.UserId = a.UserId AND active.DietPlanId = a.DietPlanId
    LEFT JOIN dbo.UserSubscriptions sub ON sub.UserId = a.UserId
    LEFT JOIN dbo.SubscriptionPlans subPlan ON subPlan.PlanId = sub.PlanId
    WHERE a.DietPlanId = @DietPlanId
    ORDER BY u.DisplayName, u.Email;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_DietPlanAssignment_Assign
    @DietPlanId UNIQUEIDENTIFIER,
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

    DECLARE @PlanName NVARCHAR(200);
    DECLARE @OwnerAdminUserId UNIQUEIDENTIFIER;
    DECLARE @Visibility NVARCHAR(20);

    SELECT @PlanName = Name,
           @OwnerAdminUserId = OwnerAdminUserId,
           @Visibility = Visibility
    FROM dbo.NutritionPlans
    WHERE DietPlanId = @DietPlanId;

    IF @PlanName IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @DietPlanId AS EntityId, N'That plan no longer exists.' AS Detail;
        RETURN;
    END

    IF @ActorCanManageAll = 0
       AND (@OwnerAdminUserId IS NULL OR @OwnerAdminUserId <> @ActorAdminUserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @DietPlanId AS EntityId, N'Only the trainer who owns this plan can assign it.' AS Detail;
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

    IF EXISTS (SELECT 1 FROM dbo.DietPlanAssignments WHERE DietPlanId = @DietPlanId AND UserId = @UserId)
    BEGIN
        UPDATE dbo.DietPlanAssignments
        SET AssignedByAdminUserId = @ActorAdminUserId,
            AssignedAtUtc = SYSUTCDATETIME()
        WHERE DietPlanId = @DietPlanId AND UserId = @UserId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.DietPlanAssignments (DietPlanId, UserId, AssignedByAdminUserId)
        VALUES (@DietPlanId, @UserId, @ActorAdminUserId);
    END

    IF @Visibility = N'Private'
    BEGIN
        UPDATE dbo.NutritionPlans SET Visibility = N'Shared' WHERE DietPlanId = @DietPlanId;
        SET @Visibility = N'Shared';
    END

    IF @SetActive = 1
    BEGIN
        MERGE dbo.UserActiveDietPlans AS target
        USING (SELECT @UserId AS UserId, @DietPlanId AS DietPlanId) AS source
        ON target.UserId = source.UserId
        WHEN MATCHED THEN
            UPDATE SET DietPlanId = source.DietPlanId, ActivatedAtUtc = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN
            INSERT (UserId, DietPlanId, ActivatedAtUtc) VALUES (source.UserId, source.DietPlanId, SYSUTCDATETIME());
    END

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Assign', N'DietPlanAssignment', CONVERT(NVARCHAR(64), @UserId),
            N'Assigned diet plan ''' + @PlanName + N''' (' + @Visibility + N') to ' + @ClientLabel
            + CASE WHEN @SetActive = 1 THEN N' as their active plan' ELSE N'' END,
            @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_DietPlanAssignment_Remove
    @DietPlanId UNIQUEIDENTIFIER,
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

    DECLARE @PlanName NVARCHAR(200);
    DECLARE @OwnerAdminUserId UNIQUEIDENTIFIER;

    SELECT @PlanName = Name,
           @OwnerAdminUserId = OwnerAdminUserId
    FROM dbo.NutritionPlans
    WHERE DietPlanId = @DietPlanId;

    IF @PlanName IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @DietPlanId AS EntityId, N'That plan no longer exists.' AS Detail;
        RETURN;
    END

    IF @ActorCanManageAll = 0
       AND (@OwnerAdminUserId IS NULL OR @OwnerAdminUserId <> @ActorAdminUserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @DietPlanId AS EntityId, N'Only the trainer who owns this plan can unassign it.' AS Detail;
        RETURN;
    END

    DECLARE @WasActive BIT = 0;

    IF EXISTS (SELECT 1 FROM dbo.UserActiveDietPlans WHERE UserId = @UserId AND DietPlanId = @DietPlanId)
        SET @WasActive = 1;

    DELETE FROM dbo.DietPlanAssignments WHERE DietPlanId = @DietPlanId AND UserId = @UserId;

    IF @@ROWCOUNT = 0
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @UserId AS EntityId, N'That client was not assigned this plan.' AS Detail;
        RETURN;
    END

    IF @WasActive = 1
    BEGIN
        DELETE FROM dbo.UserActiveDietPlans WHERE UserId = @UserId AND DietPlanId = @DietPlanId;
    END

    DECLARE @ClientLabel NVARCHAR(200) =
        (SELECT COALESCE(NULLIF(DisplayName, N''), NULLIF(Email, N''), CONVERT(NVARCHAR(64), UserId))
         FROM dbo.Users WHERE UserId = @UserId);

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Unassign', N'DietPlanAssignment', CONVERT(NVARCHAR(64), @UserId),
            N'Unassigned diet plan ''' + @PlanName + N''' from ' + ISNULL(@ClientLabel, CONVERT(NVARCHAR(64), @UserId))
            + CASE WHEN @WasActive = 1 THEN N' (and cleared it as their active plan)' ELSE N'' END,
            @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO
