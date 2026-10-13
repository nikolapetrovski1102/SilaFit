USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Normalized, source-agnostic food composition catalog. Nutrients are stored
-- per 100 g so serving conversions are deterministic across every source.
IF OBJECT_ID(N'dbo.FoodNutrition', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FoodNutrition
    (
        FoodNutritionId BIGINT IDENTITY(1,1) NOT NULL,
        Name             NVARCHAR(500)       NOT NULL,
        NormalizedName   NVARCHAR(500)       NOT NULL,
        BrandName        NVARCHAR(300)       NULL,
        Barcode          NVARCHAR(80)        NULL,
        DataType         NVARCHAR(50)        NULL,
        SourceName       NVARCHAR(40)        NOT NULL,
        SourceFoodId     NVARCHAR(120)       NOT NULL,
        SourceUrl        NVARCHAR(1000)      NULL,
        ServingSizeG     DECIMAL(12,3)       NULL,
        CaloriesKcal     DECIMAL(12,3)       NULL,
        ProteinG         DECIMAL(12,3)       NULL,
        CarbohydrateG    DECIMAL(12,3)       NULL,
        FatG             DECIMAL(12,3)       NULL,
        FiberG           DECIMAL(12,3)       NULL,
        SugarG           DECIMAL(12,3)       NULL,
        SodiumMg         DECIMAL(12,3)       NULL,
        IsBranded        BIT                 NOT NULL CONSTRAINT DF_FoodNutrition_IsBranded DEFAULT (0),
        ContentHash      BINARY(32)          NOT NULL,
        SourcePriority   AS
        (
            CONVERT(TINYINT, CASE SourceName
                WHEN N'USDA Foundation' THEN 0
                WHEN N'USDA Survey' THEN 1
                WHEN N'CNF' THEN 2
                WHEN N'CoFID' THEN 3
                WHEN N'USDA Legacy' THEN 4
                WHEN N'USDA Branded' THEN 5
                WHEN N'Open Food Facts' THEN 6
                ELSE 7
            END)
        ) PERSISTED,
        NameLength       AS (CONVERT(SMALLINT, LEN(Name))) PERSISTED,
        ImportedAtUtc    DATETIME2(3)        NOT NULL CONSTRAINT DF_FoodNutrition_ImportedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_FoodNutrition PRIMARY KEY CLUSTERED (FoodNutritionId),
        CONSTRAINT UQ_FoodNutrition_Source UNIQUE (SourceName, SourceFoodId),
        CONSTRAINT CK_FoodNutrition_HasMacro CHECK
        (
            CaloriesKcal IS NOT NULL OR ProteinG IS NOT NULL OR
            CarbohydrateG IS NOT NULL OR FatG IS NOT NULL
        )
    );

    -- Conservatively deduplicates equivalent rows across sources. The hash
    -- includes brand/barcode for packaged products, so different products are
    -- not collapsed merely because their displayed names and macros match.
    CREATE UNIQUE NONCLUSTERED INDEX UX_FoodNutrition_ContentHash
        ON dbo.FoodNutrition (ContentHash);

    CREATE NONCLUSTERED INDEX IX_FoodNutrition_SearchV2
        ON dbo.FoodNutrition (NormalizedName, SourcePriority, NameLength, FoodNutritionId)
        INCLUDE (Name, BrandName, Barcode, SourceName, ServingSizeG, CaloriesKcal,
                 ProteinG, CarbohydrateG, FatG, FiberG, SugarG, SodiumMg);

    CREATE NONCLUSTERED INDEX IX_FoodNutrition_Barcode
        ON dbo.FoodNutrition (Barcode)
        WHERE Barcode IS NOT NULL;
END
GO

-- Upgrade databases created by the initial version of this migration.
IF COL_LENGTH(N'dbo.FoodNutrition', N'SourcePriority') IS NULL
BEGIN
    ALTER TABLE dbo.FoodNutrition ADD SourcePriority AS
    (
        CONVERT(TINYINT, CASE SourceName
            WHEN N'USDA Foundation' THEN 0
            WHEN N'USDA Survey' THEN 1
            WHEN N'CNF' THEN 2
            WHEN N'CoFID' THEN 3
            WHEN N'USDA Legacy' THEN 4
            WHEN N'USDA Branded' THEN 5
            WHEN N'Open Food Facts' THEN 6
            ELSE 7
        END)
    ) PERSISTED;
END
GO

IF COL_LENGTH(N'dbo.FoodNutrition', N'NameLength') IS NULL
BEGIN
    ALTER TABLE dbo.FoodNutrition
        ADD NameLength AS (CONVERT(SMALLINT, LEN(Name))) PERSISTED;
END
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.FoodNutrition') AND name = N'IX_FoodNutrition_NormalizedName')
    DROP INDEX IX_FoodNutrition_NormalizedName ON dbo.FoodNutrition;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.FoodNutrition') AND name = N'IX_FoodNutrition_SearchV2')
BEGIN
    CREATE NONCLUSTERED INDEX IX_FoodNutrition_SearchV2
        ON dbo.FoodNutrition (NormalizedName, SourcePriority, NameLength, FoodNutritionId)
        INCLUDE (Name, BrandName, Barcode, SourceName, ServingSizeG, CaloriesKcal,
                 ProteinG, CarbohydrateG, FatG, FiberG, SugarG, SodiumMg)
        WITH (SORT_IN_TEMPDB = ON, MAXDOP = 2);
END
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.FoodNutrition') AND name = N'IX_FoodNutrition_Search')
    DROP INDEX IX_FoodNutrition_Search ON dbo.FoodNutrition;
GO
