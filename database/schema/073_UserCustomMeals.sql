USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Meals a user builds from ingredients in the diet-plan wizard
-- (usp_UserDietPlanCustomMeal_Create). They live in dbo.MealSuggestions so
-- every diet-plan read path (detail, active plan, shopping list) keeps working
-- unchanged, but are private to their owner - NULL marks the shared catalog.
-- No FK to dbo.Users, same as FoodNutrition.CreatedByUserId (066): account
-- deletion removes a user's rows explicitly (usp_Account_DeleteUserData).
IF COL_LENGTH(N'dbo.MealSuggestions', N'OwnerUserId') IS NULL
BEGIN
    ALTER TABLE dbo.MealSuggestions ADD OwnerUserId UNIQUEIDENTIFIER NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'dbo.MealSuggestions')
                 AND name = N'IX_MealSuggestions_OwnerUserId')
BEGIN
    CREATE NONCLUSTERED INDEX IX_MealSuggestions_OwnerUserId
        ON dbo.MealSuggestions (OwnerUserId)
        WHERE OwnerUserId IS NOT NULL;
END
GO
