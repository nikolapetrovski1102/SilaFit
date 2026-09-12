USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.Exercises', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Exercises
    (
        ExerciseId      UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Exercises_ExerciseId DEFAULT NEWSEQUENTIALID(),
        Name            NVARCHAR(150)    NOT NULL,
        MuscleGroup     NVARCHAR(30)     NOT NULL,
        EquipmentType   NVARCHAR(50)     NULL,
        IsCompound      BIT              NOT NULL CONSTRAINT DF_Exercises_IsCompound DEFAULT (0),
        DemoVideoUrl    NVARCHAR(500)    NULL,
        CreatedAtUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_Exercises_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Exercises PRIMARY KEY CLUSTERED (ExerciseId),
        CONSTRAINT CK_Exercises_MuscleGroup CHECK (MuscleGroup IN ('chest', 'back', 'legs', 'shoulders', 'arms', 'core'))
    );

    CREATE INDEX IX_Exercises_MuscleGroup ON dbo.Exercises(MuscleGroup);
END
GO
