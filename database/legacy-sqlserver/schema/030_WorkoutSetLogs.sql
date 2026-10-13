USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Per-set weight/reps logging. `WorkoutSessions` only ever carried the
-- session-level aggregate (TonnageKg/RpeScore) - this table is the missing
-- per-exercise history real Personal Records need. `UserId` is denormalized
-- onto every row (rather than joined through WorkoutSessions) so the PR
-- query below can scan one user's lifetime lifts without a session join.
IF OBJECT_ID(N'dbo.WorkoutSetLogs', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.WorkoutSetLogs
    (
        WorkoutSetLogId  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_WorkoutSetLogs_Id DEFAULT NEWSEQUENTIALID(),
        WorkoutSessionId UNIQUEIDENTIFIER NOT NULL,
        UserId           UNIQUEIDENTIFIER NOT NULL,
        ExerciseId       UNIQUEIDENTIFIER NOT NULL,
        SetNumber        TINYINT          NOT NULL,
        WeightKg         DECIMAL(6,2)     NOT NULL,
        Reps             SMALLINT         NOT NULL,
        CompletedAtUtc   DATETIME2(3)     NOT NULL CONSTRAINT DF_WorkoutSetLogs_CompletedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_WorkoutSetLogs PRIMARY KEY CLUSTERED (WorkoutSetLogId),
        CONSTRAINT FK_WorkoutSetLogs_WorkoutSessions FOREIGN KEY (WorkoutSessionId) REFERENCES dbo.WorkoutSessions(WorkoutSessionId),
        CONSTRAINT FK_WorkoutSetLogs_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT FK_WorkoutSetLogs_Exercises FOREIGN KEY (ExerciseId) REFERENCES dbo.Exercises(ExerciseId),
        CONSTRAINT CK_WorkoutSetLogs_SetNumber CHECK (SetNumber > 0),
        CONSTRAINT CK_WorkoutSetLogs_Reps CHECK (Reps > 0),
        CONSTRAINT CK_WorkoutSetLogs_WeightKg CHECK (WeightKg >= 0)
    );

    -- Drives `usp_WorkoutSession_GetPersonalRecords`: per user, per exercise,
    -- ordered by weight (for the PR itself) and by date (for the "what was
    -- the best before this one" delta).
    CREATE INDEX IX_WorkoutSetLogs_UserId_ExerciseId ON dbo.WorkoutSetLogs(UserId, ExerciseId, WeightKg DESC, CompletedAtUtc);

    -- Lets a session be re-completed idempotently (delete-then-reinsert by
    -- session, see `usp_WorkoutSession_Complete`).
    CREATE INDEX IX_WorkoutSetLogs_WorkoutSessionId ON dbo.WorkoutSetLogs(WorkoutSessionId);
END
GO
