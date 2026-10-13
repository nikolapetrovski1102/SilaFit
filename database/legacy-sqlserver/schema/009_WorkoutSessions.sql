USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.WorkoutSessions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.WorkoutSessions
    (
        WorkoutSessionId    UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_WorkoutSessions_Id DEFAULT NEWSEQUENTIALID(),
        UserId              UNIQUEIDENTIFIER NOT NULL,
        SplitDayId          UNIQUEIDENTIFIER NULL,
        ScheduledDateUtc    DATE             NOT NULL,
        Status              NVARCHAR(20)     NOT NULL CONSTRAINT DF_WorkoutSessions_Status DEFAULT ('Scheduled'),
        StartedAtUtc        DATETIME2(3)     NULL,
        CompletedAtUtc      DATETIME2(3)     NULL,
        DurationMinutes     SMALLINT         NULL,
        CaloriesEstimate    SMALLINT         NULL,
        RpeScore            DECIMAL(3,1)     NULL,
        TonnageKg           DECIMAL(10,2)    NULL,
        CreatedAtUtc        DATETIME2(3)     NOT NULL CONSTRAINT DF_WorkoutSessions_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_WorkoutSessions PRIMARY KEY CLUSTERED (WorkoutSessionId),
        CONSTRAINT FK_WorkoutSessions_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT FK_WorkoutSessions_SplitDays FOREIGN KEY (SplitDayId) REFERENCES dbo.SplitDays(SplitDayId),
        CONSTRAINT CK_WorkoutSessions_Status CHECK (Status IN ('Scheduled', 'Completed', 'Missed', 'ActiveRest'))
    );

    CREATE INDEX IX_WorkoutSessions_UserId_ScheduledDateUtc ON dbo.WorkoutSessions(UserId, ScheduledDateUtc);
END
GO
