USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserNutritionTargets_Get
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT UserId, TargetCalories, TargetProteinG, TargetCarbsG, TargetFatsG, UpdatedAtUtc
    FROM dbo.UserNutritionTargets
    WHERE UserId = @UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserNutritionTargets_Upsert
    @UserId UNIQUEIDENTIFIER,
    @TargetCalories SMALLINT,
    @TargetProteinG SMALLINT,
    @TargetCarbsG SMALLINT,
    @TargetFatsG SMALLINT
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.UserNutritionTargets AS target
    USING (SELECT @UserId AS UserId) AS source
        ON target.UserId = source.UserId
    WHEN MATCHED THEN
        UPDATE SET
            TargetCalories = @TargetCalories,
            TargetProteinG = @TargetProteinG,
            TargetCarbsG = @TargetCarbsG,
            TargetFatsG = @TargetFatsG,
            UpdatedAtUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (UserId, TargetCalories, TargetProteinG, TargetCarbsG, TargetFatsG)
        VALUES (@UserId, @TargetCalories, @TargetProteinG, @TargetCarbsG, @TargetFatsG);

    SELECT UserId, TargetCalories, TargetProteinG, TargetCarbsG, TargetFatsG, UpdatedAtUtc
    FROM dbo.UserNutritionTargets
    WHERE UserId = @UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_MealLogs_GetForDate
    @UserId UNIQUEIDENTIFIER,
    @LogDateUtc DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT MealLogId, UserId, LogDateUtc, MealType, Title, CaloriesKcal, ProteinG, CarbsG, FatsG,
           Status, PlannedLocalTime, LoggedAtUtc, CreatedAtUtc
    FROM dbo.MealLogs
    WHERE UserId = @UserId AND LogDateUtc = @LogDateUtc
    ORDER BY CreatedAtUtc ASC;
END
GO

-- Insert when @MealLogId is NULL, otherwise update the existing row (must
-- already belong to @UserId). Stamps LoggedAtUtc the moment Status flips to
-- 'Logged' and leaves it untouched on every other write.
CREATE OR ALTER PROCEDURE dbo.usp_MealLogs_Upsert
    @MealLogId UNIQUEIDENTIFIER = NULL,
    @UserId UNIQUEIDENTIFIER,
    @LogDateUtc DATE,
    @MealType NVARCHAR(20),
    @Title NVARCHAR(200),
    @CaloriesKcal SMALLINT,
    @ProteinG SMALLINT,
    @CarbsG SMALLINT,
    @FatsG SMALLINT,
    @Status NVARCHAR(10),
    @PlannedLocalTime TIME(0) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @MealLogId IS NULL
    BEGIN
        SET @MealLogId = NEWID();

        INSERT INTO dbo.MealLogs
            (MealLogId, UserId, LogDateUtc, MealType, Title, CaloriesKcal, ProteinG, CarbsG, FatsG,
             Status, PlannedLocalTime, LoggedAtUtc)
        VALUES
            (@MealLogId, @UserId, @LogDateUtc, @MealType, @Title, @CaloriesKcal, @ProteinG, @CarbsG, @FatsG,
             @Status, @PlannedLocalTime, CASE WHEN @Status = 'Logged' THEN SYSUTCDATETIME() ELSE NULL END);
    END
    ELSE
    BEGIN
        UPDATE dbo.MealLogs
        SET LogDateUtc = @LogDateUtc,
            MealType = @MealType,
            Title = @Title,
            CaloriesKcal = @CaloriesKcal,
            ProteinG = @ProteinG,
            CarbsG = @CarbsG,
            FatsG = @FatsG,
            Status = @Status,
            PlannedLocalTime = @PlannedLocalTime,
            LoggedAtUtc = CASE
                WHEN @Status = 'Logged' AND LoggedAtUtc IS NULL THEN SYSUTCDATETIME()
                WHEN @Status = 'Planned' THEN NULL
                ELSE LoggedAtUtc
            END
        WHERE MealLogId = @MealLogId AND UserId = @UserId;
    END

    SELECT MealLogId, UserId, LogDateUtc, MealType, Title, CaloriesKcal, ProteinG, CarbsG, FatsG,
           Status, PlannedLocalTime, LoggedAtUtc, CreatedAtUtc
    FROM dbo.MealLogs
    WHERE MealLogId = @MealLogId AND UserId = @UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_MealLogs_Delete
    @MealLogId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.MealLogs
    WHERE MealLogId = @MealLogId AND UserId = @UserId;
END
GO

-- Month-matched suggestions first, then evergreen (SuggestedMonth IS NULL)
-- ones, each group by SortOrder.
CREATE OR ALTER PROCEDURE dbo.usp_MealSuggestions_GetForMonth
    @Month TINYINT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT MealSuggestionId, Title, MealType, Description, CaloriesKcal, ProteinG, CarbsG, FatsG,
           SuggestedMonth, IsSystemDefault, SortOrder
    FROM dbo.MealSuggestions
    WHERE SuggestedMonth = @Month OR SuggestedMonth IS NULL
    ORDER BY CASE WHEN SuggestedMonth = @Month THEN 0 ELSE 1 END, SortOrder;
END
GO
