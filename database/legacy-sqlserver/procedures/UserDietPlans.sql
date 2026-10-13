USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- App-facing CRUD for a user's own diet plan, mirroring UserSplits.sql's
-- shape (same Outcome/EntityId/Detail result, same validation ranges) for
-- the meal-planning equivalent. Ownership is a direct
-- DietPlans.OwnerUserId = @UserId match, checked inside the same transaction
-- as the write. No AdminAuditLog rows - see UserSplits.sql.

CREATE OR ALTER PROCEDURE dbo.usp_UserDietPlans_GetOwned
    @UserId UNIQUEIDENTIFIER
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
           dp.SortOrder,
           dp.Visibility,
           dp.OwnerUserId,
           dp.IsAiGenerated,
           dp.AiKeptAtUtc
    FROM dbo.NutritionPlans dp
    WHERE dp.OwnerUserId = @UserId
    ORDER BY dp.SortOrder, dp.Name;
END
GO

-- @IsAiGenerated is only ever passed true by Silen.Tools.WeeklyPlanGeneration;
-- see the matching comment on usp_UserSplit_Upsert (UserSplits.sql) - same
-- rationale, left untouched on UPDATE.
CREATE OR ALTER PROCEDURE dbo.usp_UserDietPlan_Upsert
    @DietPlanId UNIQUEIDENTIFIER = NULL,
    @UserId UNIQUEIDENTIFIER,
    @Name NVARCHAR(200),
    @Description NVARCHAR(1000) = NULL,
    @HeroImageUrl NVARCHAR(500) = NULL,
    @PeriodType NVARCHAR(20) = N'Weekly',
    @DurationDays TINYINT = 7,
    @IsAiGenerated BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Name = LTRIM(RTRIM(@Name));
    SET @Description = NULLIF(LTRIM(RTRIM(@Description)), N'');
    SET @HeroImageUrl = NULLIF(LTRIM(RTRIM(@HeroImageUrl)), N'');
    SET @PeriodType = LTRIM(RTRIM(@PeriodType));

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

    IF @DietPlanId IS NULL
    BEGIN
        SET @DietPlanId = NEWID();

        -- Always Private on create, same rationale as usp_UserSplit_Upsert:
        -- this is the user's own content, not something to publish.
        INSERT INTO dbo.NutritionPlans
            (DietPlanId, Name, Description, HeroImageUrl, PeriodType, DurationDays,
             IsSystemDefault, SortOrder, Visibility, OwnerUserId, IsAiGenerated)
        VALUES
            (@DietPlanId, @Name, @Description, @HeroImageUrl, @PeriodType, @DurationDays,
             0, 0, N'Private', @UserId, @IsAiGenerated);
    END
    ELSE
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.NutritionPlans WHERE DietPlanId = @DietPlanId)
        BEGIN
            COMMIT TRANSACTION;
            SELECT 1 AS Outcome, @DietPlanId AS EntityId, N'That plan no longer exists.' AS Detail;
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.NutritionPlans WHERE DietPlanId = @DietPlanId AND OwnerUserId = @UserId)
        BEGIN
            COMMIT TRANSACTION;
            SELECT 2 AS Outcome, @DietPlanId AS EntityId, N'You can only edit plans you built yourself.' AS Detail;
            RETURN;
        END

        UPDATE dbo.NutritionPlans
        SET Name = @Name,
            Description = @Description,
            HeroImageUrl = @HeroImageUrl,
            PeriodType = @PeriodType,
            DurationDays = @DurationDays
        WHERE DietPlanId = @DietPlanId;
    END

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- Blocked outright while any user has the plan active, same guard as
-- usp_UserSplit_Delete.
CREATE OR ALTER PROCEDURE dbo.usp_UserDietPlan_Delete
    @DietPlanId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Name NVARCHAR(200);
    DECLARE @ActiveUserCount INT;

    BEGIN TRANSACTION;

    SELECT @Name = Name
    FROM dbo.NutritionPlans
    WHERE DietPlanId = @DietPlanId;

    IF @Name IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @DietPlanId AS EntityId, N'That plan no longer exists.' AS Detail;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.NutritionPlans WHERE DietPlanId = @DietPlanId AND OwnerUserId = @UserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @DietPlanId AS EntityId, N'You can only delete plans you built yourself.' AS Detail;
        RETURN;
    END

    SELECT @ActiveUserCount = COUNT(*) FROM dbo.UserActiveDietPlans WHERE DietPlanId = @DietPlanId;

    IF @ActiveUserCount > 0
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @DietPlanId AS EntityId,
               N'''' + @Name + N''' is your active plan - switch to another plan before deleting it.' AS Detail;
        RETURN;
    END

    DELETE FROM dbo.DietPlanMeals
    WHERE DietPlanDayId IN (SELECT DietPlanDayId FROM dbo.DietPlanDays WHERE DietPlanId = @DietPlanId);

    DELETE FROM dbo.DietPlanDays WHERE DietPlanId = @DietPlanId;
    DELETE FROM dbo.NutritionPlans WHERE DietPlanId = @DietPlanId;

    -- Built-from-ingredients meals (073) no plan slot points at any more.
    DELETE ms
    FROM dbo.MealSuggestions ms
    WHERE ms.OwnerUserId = @UserId
      AND NOT EXISTS (SELECT 1 FROM dbo.DietPlanMeals m WHERE m.MealSuggestionId = ms.MealSuggestionId);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserDietPlanDay_Upsert
    @DietPlanDayId UNIQUEIDENTIFIER = NULL,
    @DietPlanId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER,
    @DayIndex TINYINT,
    @Title NVARCHAR(200) = NULL
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

    IF NOT EXISTS (SELECT 1 FROM dbo.NutritionPlans WHERE DietPlanId = @DietPlanId AND OwnerUserId = @UserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @DietPlanId AS EntityId, N'You can only edit plans you built yourself.' AS Detail;
        RETURN;
    END

    IF @DayIndex < 1 OR @DayIndex > 31
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, @DietPlanId AS EntityId, N'Day index must be between 1 and 31.' AS Detail;
        RETURN;
    END

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

    IF @DietPlanDayId IS NULL
    BEGIN
        SET @DietPlanDayId = NEWID();

        INSERT INTO dbo.DietPlanDays (DietPlanDayId, DietPlanId, DayIndex, Title)
        VALUES (@DietPlanDayId, @DietPlanId, @DayIndex, @Title);
    END
    ELSE
    BEGIN
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

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanDayId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserDietPlanDay_Delete
    @DietPlanDayId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @DayIndex TINYINT;

    BEGIN TRANSACTION;

    SELECT @DayIndex = d.DayIndex
    FROM dbo.DietPlanDays d
    INNER JOIN dbo.NutritionPlans p ON p.DietPlanId = d.DietPlanId
    WHERE d.DietPlanDayId = @DietPlanDayId;

    IF @DayIndex IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @DietPlanDayId AS EntityId, N'That day no longer exists.' AS Detail;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1
                   FROM dbo.DietPlanDays d
                   INNER JOIN dbo.NutritionPlans p ON p.DietPlanId = d.DietPlanId
                   WHERE d.DietPlanDayId = @DietPlanDayId
                     AND p.OwnerUserId = @UserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @DietPlanDayId AS EntityId, N'You can only edit plans you built yourself.' AS Detail;
        RETURN;
    END

    DELETE FROM dbo.DietPlanMeals WHERE DietPlanDayId = @DietPlanDayId;
    DELETE FROM dbo.DietPlanDays WHERE DietPlanDayId = @DietPlanDayId;

    -- Built-from-ingredients meals (073) no plan slot points at any more.
    DELETE ms
    FROM dbo.MealSuggestions ms
    WHERE ms.OwnerUserId = @UserId
      AND NOT EXISTS (SELECT 1 FROM dbo.DietPlanMeals m WHERE m.MealSuggestionId = ms.MealSuggestionId);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanDayId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserDietPlanMeal_Upsert
    @DietPlanMealId UNIQUEIDENTIFIER = NULL,
    @DietPlanDayId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER,
    @MealType NVARCHAR(20),
    @MealSuggestionId UNIQUEIDENTIFIER,
    @SortOrder INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @MealType = LTRIM(RTRIM(@MealType));

    BEGIN TRANSACTION;

    DECLARE @DayIndex TINYINT;

    SELECT @DayIndex = DayIndex
    FROM dbo.DietPlanDays
    WHERE DietPlanDayId = @DietPlanDayId;

    IF @DayIndex IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @DietPlanDayId AS EntityId, N'That plan day no longer exists.' AS Detail;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1
                   FROM dbo.DietPlanDays d
                   INNER JOIN dbo.NutritionPlans p ON p.DietPlanId = d.DietPlanId
                   WHERE d.DietPlanDayId = @DietPlanDayId
                     AND p.OwnerUserId = @UserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @DietPlanDayId AS EntityId, N'You can only edit plans you built yourself.' AS Detail;
        RETURN;
    END

    IF @MealType IS NULL OR @MealType NOT IN (N'Breakfast', N'Lunch', N'Dinner', N'Snack')
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, @DietPlanDayId AS EntityId, N'Meal type must be Breakfast, Lunch, Dinner or Snack.' AS Detail;
        RETURN;
    END

    -- The shared catalog, or a meal this user built from ingredients (073).
    IF NOT EXISTS (SELECT 1
                   FROM dbo.MealSuggestions
                   WHERE MealSuggestionId = @MealSuggestionId
                     AND (OwnerUserId IS NULL OR OwnerUserId = @UserId))
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @MealSuggestionId AS EntityId, N'That meal suggestion no longer exists.' AS Detail;
        RETURN;
    END

    IF @DietPlanMealId IS NULL
    BEGIN
        SET @DietPlanMealId = NEWID();

        INSERT INTO dbo.DietPlanMeals (DietPlanMealId, DietPlanDayId, MealType, MealSuggestionId, SortOrder)
        VALUES (@DietPlanMealId, @DietPlanDayId, @MealType, @MealSuggestionId, @SortOrder);
    END
    ELSE
    BEGIN
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

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanMealId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- A meal the user builds from ingredients in the diet-plan wizard: a private
-- MealSuggestions row (073) whose macros are summed from dbo.FoodNutrition
-- (per 100 g) for the chosen grams, one "150 g Chicken breast" ingredient line
-- per food (the shape IngredientSummaryFormatter aggregates into the shopping
-- list), and the day's slot pointing at it - all in one transaction.
-- @ItemsJson: [{ "foodNutritionId": 123, "grams": 150 }, ...]. Only shared
-- catalog foods and the caller's own (066) count; others are ignored.
CREATE OR ALTER PROCEDURE dbo.usp_UserDietPlanCustomMeal_Create
    @DietPlanDayId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER,
    @MealType NVARCHAR(20),
    @Title NVARCHAR(200),
    @SortOrder INT = 0,
    @ItemsJson NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @MealType = LTRIM(RTRIM(@MealType));
    SET @Title = LTRIM(RTRIM(@Title));

    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM dbo.DietPlanDays WHERE DietPlanDayId = @DietPlanDayId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @DietPlanDayId AS EntityId, N'That plan day no longer exists.' AS Detail;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1
                   FROM dbo.DietPlanDays d
                   INNER JOIN dbo.NutritionPlans p ON p.DietPlanId = d.DietPlanId
                   WHERE d.DietPlanDayId = @DietPlanDayId
                     AND p.OwnerUserId = @UserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @DietPlanDayId AS EntityId, N'You can only edit plans you built yourself.' AS Detail;
        RETURN;
    END

    IF @MealType IS NULL OR @MealType NOT IN (N'Breakfast', N'Lunch', N'Dinner', N'Snack')
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, @DietPlanDayId AS EntityId, N'Meal type must be Breakfast, Lunch, Dinner or Snack.' AS Detail;
        RETURN;
    END

    IF @Title IS NULL OR @Title = N''
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, @DietPlanDayId AS EntityId, N'Give the meal a name.' AS Detail;
        RETURN;
    END

    DECLARE @Items TABLE
    (
        Ordinal  INT            NOT NULL PRIMARY KEY,
        Name     NVARCHAR(500)  NOT NULL,
        Grams    DECIMAL(9,1)   NOT NULL,
        Calories DECIMAL(12,3)  NOT NULL,
        Protein  DECIMAL(12,3)  NOT NULL,
        Carbs    DECIMAL(12,3)  NOT NULL,
        Fats     DECIMAL(12,3)  NOT NULL
    );

    INSERT INTO @Items (Ordinal, Name, Grams, Calories, Protein, Carbs, Fats)
    SELECT CONVERT(INT, j.[key]),
           f.Name,
           i.Grams,
           ISNULL(f.CaloriesKcal, 0) * i.Grams / 100,
           ISNULL(f.ProteinG, 0) * i.Grams / 100,
           ISNULL(f.CarbohydrateG, 0) * i.Grams / 100,
           ISNULL(f.FatG, 0) * i.Grams / 100
    FROM OPENJSON(@ItemsJson) j
    CROSS APPLY OPENJSON(j.[value])
    WITH (
        FoodNutritionId BIGINT       '$.foodNutritionId',
        Grams           DECIMAL(9,1) '$.grams'
    ) i
    INNER JOIN dbo.FoodNutrition f ON f.FoodNutritionId = i.FoodNutritionId
    WHERE i.Grams > 0 AND i.Grams <= 5000
      AND (f.CreatedByUserId IS NULL OR f.CreatedByUserId = @UserId);

    IF NOT EXISTS (SELECT 1 FROM @Items)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, @DietPlanDayId AS EntityId, N'Add at least one ingredient.' AS Detail;
        RETURN;
    END

    DECLARE @MealSuggestionId UNIQUEIDENTIFIER = NEWID();
    DECLARE @DietPlanMealId UNIQUEIDENTIFIER = NEWID();

    INSERT INTO dbo.MealSuggestions
        (MealSuggestionId, Title, MealType, CaloriesKcal, ProteinG, CarbsG, FatsG,
         SuggestedMonth, IsSystemDefault, SortOrder, OwnerUserId)
    SELECT @MealSuggestionId, @Title, @MealType,
           CONVERT(SMALLINT, ROUND(SUM(Calories), 0)),
           CONVERT(SMALLINT, ROUND(SUM(Protein), 0)),
           CONVERT(SMALLINT, ROUND(SUM(Carbs), 0)),
           CONVERT(SMALLINT, ROUND(SUM(Fats), 0)),
           NULL, 0, 0, @UserId
    FROM @Items;

    INSERT INTO dbo.MealSuggestionIngredients (MealSuggestionId, SortOrder, IngredientText)
    SELECT @MealSuggestionId,
           CONVERT(SMALLINT, ROW_NUMBER() OVER (ORDER BY Ordinal) - 1),
           LEFT(CONVERT(NVARCHAR(20), CONVERT(INT, ROUND(Grams, 0))) + N' g ' + Name, 1000)
    FROM @Items;

    INSERT INTO dbo.DietPlanMeals (DietPlanMealId, DietPlanDayId, MealType, MealSuggestionId, SortOrder)
    VALUES (@DietPlanMealId, @DietPlanDayId, @MealType, @MealSuggestionId, @SortOrder);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanMealId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserDietPlanMeal_Delete
    @DietPlanMealId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Found BIT = 0;

    BEGIN TRANSACTION;

    IF EXISTS (SELECT 1 FROM dbo.DietPlanMeals WHERE DietPlanMealId = @DietPlanMealId)
        SET @Found = 1;

    IF @Found = 0
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @DietPlanMealId AS EntityId, N'That meal slot no longer exists.' AS Detail;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1
                   FROM dbo.DietPlanMeals m
                   INNER JOIN dbo.DietPlanDays d ON d.DietPlanDayId = m.DietPlanDayId
                   INNER JOIN dbo.NutritionPlans p ON p.DietPlanId = d.DietPlanId
                   WHERE m.DietPlanMealId = @DietPlanMealId
                     AND p.OwnerUserId = @UserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @DietPlanMealId AS EntityId, N'You can only edit plans you built yourself.' AS Detail;
        RETURN;
    END

    DELETE FROM dbo.DietPlanMeals WHERE DietPlanMealId = @DietPlanMealId;

    -- Built-from-ingredients meals (073) no plan slot points at any more.
    DELETE ms
    FROM dbo.MealSuggestions ms
    WHERE ms.OwnerUserId = @UserId
      AND NOT EXISTS (SELECT 1 FROM dbo.DietPlanMeals m WHERE m.MealSuggestionId = ms.MealSuggestionId);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanMealId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- Marks an AI-generated plan as permanent, diet-plan counterpart of
-- usp_UserSplit_Keep (see UserSplits.sql for the full rationale).
CREATE OR ALTER PROCEDURE dbo.usp_UserDietPlan_Keep
    @DietPlanId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM dbo.NutritionPlans WHERE DietPlanId = @DietPlanId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @DietPlanId AS EntityId, N'That plan no longer exists.' AS Detail;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.NutritionPlans WHERE DietPlanId = @DietPlanId AND OwnerUserId = @UserId)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @DietPlanId AS EntityId, N'You can only keep plans you built yourself.' AS Detail;
        RETURN;
    END

    UPDATE dbo.NutritionPlans
    SET AiKeptAtUtc = SYSUTCDATETIME()
    WHERE DietPlanId = @DietPlanId
      AND IsAiGenerated = 1
      AND AiKeptAtUtc IS NULL;

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @DietPlanId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- Sets a user's current diet plan, mirroring dbo.usp_UserActiveSplit_Set
-- (see Splits.sql). Written by the app's activate endpoint and, for on-demand
-- AI generation only, by Silen.Services. UserActiveDietPlans is still just a
-- label (048_DietPlanTrainerSharing.sql):
-- it does not pre-populate MealLogs; the Nutrition screen reads it through
-- usp_UserActiveDietPlan_Get and renders the plan's meals for the viewed day.
CREATE OR ALTER PROCEDURE dbo.usp_UserActiveDietPlan_Set
    @UserId UNIQUEIDENTIFIER,
    @DietPlanId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.UserActiveDietPlans AS target
    USING (SELECT @UserId AS UserId, @DietPlanId AS DietPlanId) AS source
    ON target.UserId = source.UserId
    WHEN MATCHED THEN
        UPDATE SET DietPlanId = source.DietPlanId, ActivatedAtUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (UserId, DietPlanId, ActivatedAtUtc) VALUES (source.UserId, source.DietPlanId, SYSUTCDATETIME());
END
GO

-- The caller's current diet plan header, or no row when none is active. The
-- app then loads the plan's days/meals through usp_DietPlans_GetDetail, so this
-- stays a single-row lookup rather than duplicating the detail result sets.
CREATE OR ALTER PROCEDURE dbo.usp_UserActiveDietPlan_Get
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT a.UserId, a.DietPlanId, a.ActivatedAtUtc, p.Name, p.DurationDays
    FROM dbo.UserActiveDietPlans a
    INNER JOIN dbo.NutritionPlans p ON p.DietPlanId = a.DietPlanId
    WHERE a.UserId = @UserId;
END
GO
