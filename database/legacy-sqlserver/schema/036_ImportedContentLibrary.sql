USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Source metadata for imported workout programs. The existing columns remain
-- the compact shape consumed by the mobile app; these columns preserve the
-- richer source material without changing that API contract.
IF COL_LENGTH(N'dbo.WorkoutSplits', N'SourceUrl') IS NULL
    ALTER TABLE dbo.WorkoutSplits ADD SourceUrl NVARCHAR(500) NULL;
GO
IF COL_LENGTH(N'dbo.WorkoutSplits', N'SourceAuthor') IS NULL
    ALTER TABLE dbo.WorkoutSplits ADD SourceAuthor NVARCHAR(300) NULL;
GO
IF COL_LENGTH(N'dbo.WorkoutSplits', N'FullDescription') IS NULL
    ALTER TABLE dbo.WorkoutSplits ADD FullDescription NVARCHAR(MAX) NULL;
GO
IF COL_LENGTH(N'dbo.WorkoutSplits', N'PopularityRank') IS NULL
    ALTER TABLE dbo.WorkoutSplits ADD PopularityRank SMALLINT NULL;
GO
IF COL_LENGTH(N'dbo.WorkoutSplits', N'PopularityWindow') IS NULL
    ALTER TABLE dbo.WorkoutSplits ADD PopularityWindow NVARCHAR(100) NULL;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_WorkoutSplits_SourceUrl')
    DROP INDEX UX_WorkoutSplits_SourceUrl ON dbo.WorkoutSplits;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_WorkoutSplits_SourceUrl')
    CREATE INDEX IX_WorkoutSplits_SourceUrl ON dbo.WorkoutSplits(SourceUrl);
GO

IF COL_LENGTH(N'dbo.SplitDays', N'SourceNotes') IS NULL
    ALTER TABLE dbo.SplitDays ADD SourceNotes NVARCHAR(MAX) NULL;
GO

IF COL_LENGTH(N'dbo.SplitDayExercises', N'SourceSets') IS NULL
    ALTER TABLE dbo.SplitDayExercises ADD SourceSets NVARCHAR(100) NULL;
GO
IF COL_LENGTH(N'dbo.SplitDayExercises', N'SourceReps') IS NULL
    ALTER TABLE dbo.SplitDayExercises ADD SourceReps NVARCHAR(300) NULL;
GO

-- MealSuggestions is the app's recipe catalog. These optional source columns
-- add the complete recipe while keeping existing readers/writers compatible.
IF COL_LENGTH(N'dbo.MealSuggestions', N'SourceUrl') IS NULL
    ALTER TABLE dbo.MealSuggestions ADD SourceUrl NVARCHAR(500) NULL;
GO
IF COL_LENGTH(N'dbo.MealSuggestions', N'ImageUrl') IS NULL
    ALTER TABLE dbo.MealSuggestions ADD ImageUrl NVARCHAR(500) NULL;
GO
IF COL_LENGTH(N'dbo.MealSuggestions', N'ServingSuggestion') IS NULL
    ALTER TABLE dbo.MealSuggestions ADD ServingSuggestion NVARCHAR(1000) NULL;
GO
IF COL_LENGTH(N'dbo.MealSuggestions', N'ContentText') IS NULL
    ALTER TABLE dbo.MealSuggestions ADD ContentText NVARCHAR(MAX) NULL;
GO
IF COL_LENGTH(N'dbo.MealSuggestions', N'CategoriesJson') IS NULL
    ALTER TABLE dbo.MealSuggestions ADD CategoriesJson NVARCHAR(MAX) NULL;
GO
IF COL_LENGTH(N'dbo.MealSuggestions', N'SourceMacrosJson') IS NULL
    ALTER TABLE dbo.MealSuggestions ADD SourceMacrosJson NVARCHAR(1000) NULL;
GO
IF COL_LENGTH(N'dbo.MealSuggestions', N'ReadCount') IS NULL
    ALTER TABLE dbo.MealSuggestions ADD ReadCount INT NULL;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_MealSuggestions_SourceUrl')
    DROP INDEX UX_MealSuggestions_SourceUrl ON dbo.MealSuggestions;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MealSuggestions_SourceUrl')
    CREATE INDEX IX_MealSuggestions_SourceUrl ON dbo.MealSuggestions(SourceUrl);
GO

IF OBJECT_ID(N'dbo.MealSuggestionIngredients', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MealSuggestionIngredients
    (
        MealSuggestionIngredientId UNIQUEIDENTIFIER NOT NULL
            CONSTRAINT DF_MealSuggestionIngredients_Id DEFAULT NEWSEQUENTIALID(),
        MealSuggestionId           UNIQUEIDENTIFIER NOT NULL,
        SortOrder                  SMALLINT NOT NULL,
        IngredientText             NVARCHAR(1000) NOT NULL,

        CONSTRAINT PK_MealSuggestionIngredients PRIMARY KEY CLUSTERED (MealSuggestionIngredientId),
        CONSTRAINT FK_MealSuggestionIngredients_MealSuggestions FOREIGN KEY (MealSuggestionId)
            REFERENCES dbo.MealSuggestions(MealSuggestionId) ON DELETE CASCADE,
        CONSTRAINT UQ_MealSuggestionIngredients_Order UNIQUE (MealSuggestionId, SortOrder)
    );
END
GO

IF OBJECT_ID(N'dbo.MealSuggestionInstructions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MealSuggestionInstructions
    (
        MealSuggestionInstructionId UNIQUEIDENTIFIER NOT NULL
            CONSTRAINT DF_MealSuggestionInstructions_Id DEFAULT NEWSEQUENTIALID(),
        MealSuggestionId            UNIQUEIDENTIFIER NOT NULL,
        SortOrder                   SMALLINT NOT NULL,
        InstructionText             NVARCHAR(2000) NOT NULL,

        CONSTRAINT PK_MealSuggestionInstructions PRIMARY KEY CLUSTERED (MealSuggestionInstructionId),
        CONSTRAINT FK_MealSuggestionInstructions_MealSuggestions FOREIGN KEY (MealSuggestionId)
            REFERENCES dbo.MealSuggestions(MealSuggestionId) ON DELETE CASCADE,
        CONSTRAINT UQ_MealSuggestionInstructions_Order UNIQUE (MealSuggestionId, SortOrder)
    );
END
GO

-- Diet guides are long-form plans rather than recipes, so their complete text
-- and ordered sections are stored separately from meal suggestions.
IF OBJECT_ID(N'dbo.DietPlans', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DietPlans
    (
        DietPlanId       UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_DietPlans_Id DEFAULT NEWSEQUENTIALID(),
        Title            NVARCHAR(200) NOT NULL,
        Summary          NVARCHAR(1000) NULL,
        ContentText      NVARCHAR(MAX) NOT NULL,
        ImageUrl         NVARCHAR(500) NULL,
        SourceUrl        NVARCHAR(500) NOT NULL,
        SourceAuthor     NVARCHAR(300) NULL,
        IsSystemDefault  BIT NOT NULL CONSTRAINT DF_DietPlans_IsSystemDefault DEFAULT (1),
        SortOrder        INT NOT NULL CONSTRAINT DF_DietPlans_SortOrder DEFAULT (0),
        CreatedAtUtc     DATETIME2(3) NOT NULL CONSTRAINT DF_DietPlans_CreatedAtUtc DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_DietPlans PRIMARY KEY CLUSTERED (DietPlanId),
        CONSTRAINT UQ_DietPlans_SourceUrl UNIQUE (SourceUrl)
    );
END
GO

IF OBJECT_ID(N'dbo.DietPlanSections', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DietPlanSections
    (
        DietPlanSectionId UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_DietPlanSections_Id DEFAULT NEWSEQUENTIALID(),
        DietPlanId        UNIQUEIDENTIFIER NOT NULL,
        SortOrder         SMALLINT NOT NULL,
        Heading           NVARCHAR(500) NULL,
        BodyText          NVARCHAR(MAX) NULL,
        ListsJson         NVARCHAR(MAX) NULL,
        TablesJson        NVARCHAR(MAX) NULL,

        CONSTRAINT PK_DietPlanSections PRIMARY KEY CLUSTERED (DietPlanSectionId),
        CONSTRAINT FK_DietPlanSections_DietPlans FOREIGN KEY (DietPlanId)
            REFERENCES dbo.DietPlans(DietPlanId) ON DELETE CASCADE,
        CONSTRAINT UQ_DietPlanSections_Order UNIQUE (DietPlanId, SortOrder)
    );
END
GO
