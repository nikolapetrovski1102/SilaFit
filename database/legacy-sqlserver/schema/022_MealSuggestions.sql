USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Curated meal-idea library for the Nutrition screen's "Suggested this
-- month" strip - same shape as dbo.WorkoutSplits: a system-authored,
-- seeded catalog (see database/seed/003_SeedMealSuggestions.sql), not a
-- live external API call. SuggestedMonth tags which calendar month (1-12)
-- a suggestion is surfaced in; NULL means it's evergreen and shows in
-- every month.
IF OBJECT_ID(N'dbo.MealSuggestions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MealSuggestions
    (
        MealSuggestionId UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_MealSuggestions_MealSuggestionId DEFAULT (NEWSEQUENTIALID()),
        Title            NVARCHAR(200)    NOT NULL,
        MealType         NVARCHAR(20)     NOT NULL CONSTRAINT CK_MealSuggestions_MealType CHECK (MealType IN ('Breakfast', 'Lunch', 'Dinner', 'Snack')),
        Description      NVARCHAR(500)    NULL,
        CaloriesKcal     SMALLINT         NOT NULL,
        ProteinG         SMALLINT         NOT NULL,
        CarbsG           SMALLINT         NOT NULL,
        FatsG            SMALLINT         NOT NULL,
        SuggestedMonth   TINYINT          NULL CONSTRAINT CK_MealSuggestions_SuggestedMonth CHECK (SuggestedMonth BETWEEN 1 AND 12),
        IsSystemDefault  BIT              NOT NULL CONSTRAINT DF_MealSuggestions_IsSystemDefault DEFAULT (1),
        SortOrder        INT              NOT NULL CONSTRAINT DF_MealSuggestions_SortOrder DEFAULT (0),
        CreatedAtUtc     DATETIME2(3)     NOT NULL CONSTRAINT DF_MealSuggestions_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_MealSuggestions PRIMARY KEY CLUSTERED (MealSuggestionId)
    );

    CREATE NONCLUSTERED INDEX IX_MealSuggestions_SuggestedMonth ON dbo.MealSuggestions (SuggestedMonth);
END
GO
