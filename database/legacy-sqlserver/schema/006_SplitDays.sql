USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.SplitDays', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SplitDays
    (
        SplitDayId          UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_SplitDays_SplitDayId DEFAULT NEWSEQUENTIALID(),
        SplitId             UNIQUEIDENTIFIER NOT NULL,
        DayIndex            TINYINT          NOT NULL,
        Title               NVARCHAR(150)    NOT NULL,
        FocusLabel          NVARCHAR(100)    NULL,
        EstimatedMinutes    SMALLINT         NOT NULL CONSTRAINT DF_SplitDays_EstimatedMinutes DEFAULT (45),
        IsRestDay           BIT              NOT NULL CONSTRAINT DF_SplitDays_IsRestDay DEFAULT (0),

        CONSTRAINT PK_SplitDays PRIMARY KEY CLUSTERED (SplitDayId),
        CONSTRAINT FK_SplitDays_WorkoutSplits FOREIGN KEY (SplitId) REFERENCES dbo.WorkoutSplits(SplitId),
        CONSTRAINT UQ_SplitDays_SplitDayIndex UNIQUE (SplitId, DayIndex)
    );
END
GO
