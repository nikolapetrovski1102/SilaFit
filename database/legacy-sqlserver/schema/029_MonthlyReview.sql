USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Audit + idempotency for the monthly review batch
-- (Silen.Tools.MonthlyReview -> IMonthlyReviewService). The batch walks every
-- active ADVANCED subscriber, generates/reuses their MonthlyAnalyticsReports
-- row for the period, and emails the overview. These tables record each run
-- and each per-user delivery so re-running a period never double-emails anyone
-- and a failed send can be retried by a later run.
IF OBJECT_ID(N'dbo.MonthlyReviewRuns', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MonthlyReviewRuns
    (
        RunId               UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_MonthlyReviewRuns PRIMARY KEY CLUSTERED,
        PeriodYear          SMALLINT         NOT NULL,
        PeriodMonth         TINYINT          NOT NULL,
        PlanCode            NVARCHAR(30)     NOT NULL,
        Status              NVARCHAR(20)     NOT NULL CONSTRAINT DF_MonthlyReviewRuns_Status DEFAULT ('Running'),
        UsersConsidered     INT              NOT NULL CONSTRAINT DF_MonthlyReviewRuns_UsersConsidered DEFAULT (0),
        ReportsGenerated    INT              NOT NULL CONSTRAINT DF_MonthlyReviewRuns_ReportsGenerated DEFAULT (0),
        EmailsSent          INT              NOT NULL CONSTRAINT DF_MonthlyReviewRuns_EmailsSent DEFAULT (0),
        Failures            INT              NOT NULL CONSTRAINT DF_MonthlyReviewRuns_Failures DEFAULT (0),
        StartedAtUtc        DATETIME2(3)     NOT NULL CONSTRAINT DF_MonthlyReviewRuns_StartedAtUtc DEFAULT (SYSUTCDATETIME()),
        CompletedAtUtc      DATETIME2(3)     NULL,

        CONSTRAINT CK_MonthlyReviewRuns_PeriodMonth CHECK (PeriodMonth BETWEEN 1 AND 12),
        CONSTRAINT CK_MonthlyReviewRuns_Status CHECK (Status IN ('Running', 'Completed', 'Failed'))
    );

    CREATE INDEX IX_MonthlyReviewRuns_Period ON dbo.MonthlyReviewRuns(PeriodYear, PeriodMonth);
END
GO

IF OBJECT_ID(N'dbo.MonthlyReviewDeliveries', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MonthlyReviewDeliveries
    (
        DeliveryId      UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_MonthlyReviewDeliveries PRIMARY KEY CLUSTERED,
        RunId           UNIQUEIDENTIFIER NOT NULL,
        UserId          UNIQUEIDENTIFIER NOT NULL,
        PeriodYear      SMALLINT         NOT NULL,
        PeriodMonth     TINYINT          NOT NULL,
        Status          NVARCHAR(20)     NOT NULL,
        ErrorMessage    NVARCHAR(1000)   NULL,
        GeneratedAtUtc  DATETIME2(3)     NULL,
        EmailedAtUtc    DATETIME2(3)     NULL,
        CreatedAtUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_MonthlyReviewDeliveries_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT FK_MonthlyReviewDeliveries_Runs FOREIGN KEY (RunId) REFERENCES dbo.MonthlyReviewRuns(RunId),
        CONSTRAINT FK_MonthlyReviewDeliveries_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT CK_MonthlyReviewDeliveries_PeriodMonth CHECK (PeriodMonth BETWEEN 1 AND 12),
        CONSTRAINT CK_MonthlyReviewDeliveries_Status CHECK (Status IN ('Generated', 'Emailed', 'Skipped', 'Failed'))
    );

    -- Drives the "already emailed this period?" lookup that makes a re-run idempotent.
    CREATE INDEX IX_MonthlyReviewDeliveries_Period_Status ON dbo.MonthlyReviewDeliveries(PeriodYear, PeriodMonth, Status);
    CREATE INDEX IX_MonthlyReviewDeliveries_UserId ON dbo.MonthlyReviewDeliveries(UserId);
END
GO
