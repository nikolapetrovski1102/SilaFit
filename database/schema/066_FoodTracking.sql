USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Food-by-food meal logging (Free tier): a user can add a food the catalog
-- doesn't have. Those rows live in dbo.FoodNutrition alongside the imported
-- sources (SourceName = 'User') but are private to their creator - NULL marks
-- a shared catalog row. No FK to dbo.Users: the catalog is bulk-merged by the
-- importer, and account deletion removes a user's rows explicitly
-- (usp_Account_DeleteUserData).
IF COL_LENGTH(N'dbo.FoodNutrition', N'CreatedByUserId') IS NULL
BEGIN
    ALTER TABLE dbo.FoodNutrition ADD CreatedByUserId UNIQUEIDENTIFIER NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'dbo.FoodNutrition')
                 AND name = N'IX_FoodNutrition_CreatedByUserId')
BEGIN
    CREATE NONCLUSTERED INDEX IX_FoodNutrition_CreatedByUserId
        ON dbo.FoodNutrition (CreatedByUserId, NormalizedName)
        WHERE CreatedByUserId IS NOT NULL;
END
GO

-- Final covering index for the shared catalog. Created here (rather than in
-- 065) because CreatedByUserId is introduced above and must be available as an
-- included column for the shared/private visibility predicate to stay covered.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'dbo.FoodNutrition')
                 AND name = N'IX_FoodNutrition_SearchV4')
BEGIN
    CREATE NONCLUSTERED INDEX IX_FoodNutrition_SearchV4
        ON dbo.FoodNutrition (NormalizedName, FoodNutritionId)
        INCLUDE (Name, BrandName, Barcode, SourceName, ServingSizeG, CaloriesKcal,
                 ProteinG, CarbohydrateG, FatG, FiberG, SugarG, SodiumMg, CreatedByUserId)
        WITH (SORT_IN_TEMPDB = ON, MAXDOP = 2);
END
GO

IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE object_id = OBJECT_ID(N'dbo.FoodNutrition')
             AND name = N'IX_FoodNutrition_SearchV3')
    DROP INDEX IX_FoodNutrition_SearchV3 ON dbo.FoodNutrition;
GO

IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE object_id = OBJECT_ID(N'dbo.FoodNutrition')
             AND name = N'IX_FoodNutrition_SearchV2')
    DROP INDEX IX_FoodNutrition_SearchV2 ON dbo.FoodNutrition;
GO

-- The foods a meal was built from, as AES-256-GCM ciphertext of a JSON array
-- (Silen.Common.Helpers.FieldCipher, encrypted at MealPlanningProvider like
-- the rest of the row). NULL for meals logged as a single macro total -
-- planned diet-plan meals and every meal logged before this column existed.
IF COL_LENGTH(N'dbo.MealLogs', N'Items') IS NULL
BEGIN
    ALTER TABLE dbo.MealLogs ADD Items VARBINARY(MAX) NULL;
END
GO
