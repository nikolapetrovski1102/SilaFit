USE SilenDb;
GO

-- Source-declared workout requirements used by the automatic split matcher.
-- Columns are nullable so trainer-created and legacy splits remain compatible.
IF COL_LENGTH(N'dbo.WorkoutSplits', N'DaysPerWeek') IS NULL
    ALTER TABLE dbo.WorkoutSplits ADD DaysPerWeek TINYINT NULL;
GO
IF COL_LENGTH(N'dbo.WorkoutSplits', N'ProgramDurationWeeks') IS NULL
    ALTER TABLE dbo.WorkoutSplits ADD ProgramDurationWeeks SMALLINT NULL;
GO
IF COL_LENGTH(N'dbo.WorkoutSplits', N'MinSessionMinutes') IS NULL
    ALTER TABLE dbo.WorkoutSplits ADD MinSessionMinutes SMALLINT NULL;
GO
IF COL_LENGTH(N'dbo.WorkoutSplits', N'MaxSessionMinutes') IS NULL
    ALTER TABLE dbo.WorkoutSplits ADD MaxSessionMinutes SMALLINT NULL;
GO
IF COL_LENGTH(N'dbo.WorkoutSplits', N'EquipmentRequired') IS NULL
    ALTER TABLE dbo.WorkoutSplits ADD EquipmentRequired NVARCHAR(500) NULL;
GO
IF COL_LENGTH(N'dbo.WorkoutSplits', N'TargetGender') IS NULL
    ALTER TABLE dbo.WorkoutSplits ADD TargetGender NVARCHAR(50) NULL;
GO
IF COL_LENGTH(N'dbo.WorkoutSplits', N'WorkoutTypeLabel') IS NULL
    ALTER TABLE dbo.WorkoutSplits ADD WorkoutTypeLabel NVARCHAR(100) NULL;
GO
IF COL_LENGTH(N'dbo.WorkoutSplits', N'SourceCategoriesJson') IS NULL
    ALTER TABLE dbo.WorkoutSplits ADD SourceCategoriesJson NVARCHAR(MAX) NULL;
GO
IF COL_LENGTH(N'dbo.WorkoutSplits', N'CatalogRank') IS NULL
    ALTER TABLE dbo.WorkoutSplits ADD CatalogRank INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_WorkoutSplits_Recommendation')
    CREATE INDEX IX_WorkoutSplits_Recommendation
        ON dbo.WorkoutSplits(IsSystemDefault, RecommendedGoal, Level, DaysPerWeek)
        INCLUDE (TargetGender, MinSessionMinutes, MaxSessionMinutes, SortOrder);
GO
