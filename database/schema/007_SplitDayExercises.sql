USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.SplitDayExercises', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SplitDayExercises
    (
        SplitDayExerciseId  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_SplitDayExercises_Id DEFAULT NEWSEQUENTIALID(),
        SplitDayId          UNIQUEIDENTIFIER NOT NULL,
        ExerciseId          UNIQUEIDENTIFIER NOT NULL,
        SortOrder           TINYINT          NOT NULL,
        TargetSets          TINYINT          NOT NULL,
        TargetRepsLow       TINYINT          NOT NULL,
        TargetRepsHigh      TINYINT          NOT NULL,

        CONSTRAINT PK_SplitDayExercises PRIMARY KEY CLUSTERED (SplitDayExerciseId),
        CONSTRAINT FK_SplitDayExercises_SplitDays FOREIGN KEY (SplitDayId) REFERENCES dbo.SplitDays(SplitDayId),
        CONSTRAINT FK_SplitDayExercises_Exercises FOREIGN KEY (ExerciseId) REFERENCES dbo.Exercises(ExerciseId)
    );

    CREATE INDEX IX_SplitDayExercises_SplitDayId ON dbo.SplitDayExercises(SplitDayId);
END
GO
