USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- One meal slot within a diet-plan day, referencing the existing
-- MealSuggestions catalog rather than freeform macro entry (mirrors
-- dbo.SplitDayExercises referencing dbo.Exercises). Not unique on
-- (DietPlanDayId, MealType) so a day can carry more than one Snack.
IF OBJECT_ID(N'dbo.DietPlanMeals', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DietPlanMeals
    (
        DietPlanMealId   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_DietPlanMeals_DietPlanMealId DEFAULT (NEWID()),
        DietPlanDayId    UNIQUEIDENTIFIER NOT NULL,
        MealType         NVARCHAR(20)     NOT NULL,
        MealSuggestionId UNIQUEIDENTIFIER NOT NULL,
        SortOrder        INT              NOT NULL CONSTRAINT DF_DietPlanMeals_SortOrder DEFAULT (0),

        CONSTRAINT PK_DietPlanMeals PRIMARY KEY CLUSTERED (DietPlanMealId),
        CONSTRAINT CK_DietPlanMeals_MealType CHECK (MealType IN (N'Breakfast', N'Lunch', N'Dinner', N'Snack')),
        CONSTRAINT FK_DietPlanMeals_DietPlanDays FOREIGN KEY (DietPlanDayId)
            REFERENCES dbo.DietPlanDays(DietPlanDayId) ON DELETE CASCADE,
        CONSTRAINT FK_DietPlanMeals_MealSuggestions FOREIGN KEY (MealSuggestionId)
            REFERENCES dbo.MealSuggestions(MealSuggestionId)
    );

    CREATE INDEX IX_DietPlanMeals_DietPlanDayId ON dbo.DietPlanMeals(DietPlanDayId);
    CREATE INDEX IX_DietPlanMeals_MealSuggestionId ON dbo.DietPlanMeals(MealSuggestionId);
END
GO
