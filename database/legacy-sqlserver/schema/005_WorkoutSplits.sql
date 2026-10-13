USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.WorkoutSplits', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.WorkoutSplits
    (
        SplitId         UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_WorkoutSplits_SplitId DEFAULT NEWSEQUENTIALID(),
        Name            NVARCHAR(150)    NOT NULL,
        Category        NVARCHAR(50)     NOT NULL,
        Level           NVARCHAR(20)     NOT NULL CONSTRAINT DF_WorkoutSplits_Level DEFAULT ('Intermediate'),
        DurationDays    TINYINT          NOT NULL,
        Description     NVARCHAR(500)    NULL,
        HeroImageUrl    NVARCHAR(500)    NULL,
        IsSystemDefault BIT              NOT NULL CONSTRAINT DF_WorkoutSplits_IsSystemDefault DEFAULT (0),
        SortOrder       INT              NOT NULL CONSTRAINT DF_WorkoutSplits_SortOrder DEFAULT (0),
        CreatedAtUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_WorkoutSplits_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_WorkoutSplits PRIMARY KEY CLUSTERED (SplitId),
        CONSTRAINT CK_WorkoutSplits_Category CHECK (Category IN ('PushPullLegs', 'UpperLower', 'FullBody', 'ArnoldSplit')),
        CONSTRAINT CK_WorkoutSplits_Level CHECK (Level IN ('Beginner', 'Intermediate', 'Advanced'))
    );
END
GO
