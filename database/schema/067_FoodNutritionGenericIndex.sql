USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Generic (non-branded) reference foods - USDA Foundation/Survey/Legacy, CNF,
-- CoFID - are ~1% of the catalog, but they're what a search like "egg" should
-- surface first. Without their own index they sit among millions of branded
-- rows in IX_FoodNutrition_SearchV4, so an exact branded match ("EGG" from
-- dozens of brands) fills the result before a generic "Egg, whole, raw" is
-- ever reached. FoodNutrition_Search reads this index first. The filter lists
-- the generic sources explicitly: a newly imported generic source must be
-- added here and to the procedure's matching predicate.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'dbo.FoodNutrition')
                 AND name = N'IX_FoodNutrition_Generic')
BEGIN
    CREATE NONCLUSTERED INDEX IX_FoodNutrition_Generic
        ON dbo.FoodNutrition (NormalizedName, FoodNutritionId)
        INCLUDE (Name, SourceName)
        WHERE SourceName IN (N'USDA Foundation', N'USDA Survey', N'CNF', N'CoFID', N'USDA Legacy')
        WITH (SORT_IN_TEMPDB = ON, MAXDOP = 2);
END
GO
