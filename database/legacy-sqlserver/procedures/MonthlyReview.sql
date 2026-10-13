USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Opens one monthly review run. RunId is generated here so the caller (and every
-- per-user delivery row written afterwards) shares the same identifier even if
-- the worker process is restarted mid-batch.
CREATE OR ALTER PROCEDURE dbo.usp_MonthlyReview_StartRun
    @PeriodYear  SMALLINT,
    @PeriodMonth TINYINT,
    @PlanCode    NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RunId UNIQUEIDENTIFIER = NEWID();

    INSERT INTO dbo.MonthlyReviewRuns (RunId, PeriodYear, PeriodMonth, PlanCode, Status)
    VALUES (@RunId, @PeriodYear, @PeriodMonth, @PlanCode, 'Running');

    SELECT RunId, PeriodYear, PeriodMonth, PlanCode, Status,
           UsersConsidered, ReportsGenerated, EmailsSent, Failures,
           StartedAtUtc, CompletedAtUtc
    FROM dbo.MonthlyReviewRuns
    WHERE RunId = @RunId;
END
GO

-- Finalises a run with its aggregate counters. Called even when some users
-- failed: Status stays 'Completed' and Failures captures the per-user errors
-- (full detail lives in MonthlyReviewDeliveries).
CREATE OR ALTER PROCEDURE dbo.usp_MonthlyReview_CompleteRun
    @RunId            UNIQUEIDENTIFIER,
    @Status           NVARCHAR(20),
    @UsersConsidered  INT,
    @ReportsGenerated INT,
    @EmailsSent       INT,
    @Failures         INT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.MonthlyReviewRuns
    SET Status = @Status,
        CompletedAtUtc = SYSUTCDATETIME(),
        UsersConsidered = @UsersConsidered,
        ReportsGenerated = @ReportsGenerated,
        EmailsSent = @EmailsSent,
        Failures = @Failures
    WHERE RunId = @RunId;
END
GO

-- Users who already received an email for this period, scoped to one audience
-- (Subscriber = full report, Upsell = non-paying teaser) because the two passes
-- are independent: a free user who upgrades mid-period must still be eligible
-- for the full report even though they already got the teaser.
CREATE OR ALTER PROCEDURE dbo.usp_MonthlyReview_GetEmailedUserIds
    @PeriodYear   SMALLINT,
    @PeriodMonth  TINYINT,
    @DeliveryKind NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT UserId
    FROM dbo.MonthlyReviewDeliveries
    WHERE PeriodYear = @PeriodYear
      AND PeriodMonth = @PeriodMonth
      AND DeliveryKind = @DeliveryKind
      AND Status = 'Emailed';
END
GO

-- One audit row per user considered by a run: what happened (Generated /
-- Emailed / Skipped / Failed) and, on failure, why. @DeliveryKind tags which
-- audience the row belongs to (see 042_MonthlyReviewUpsell.sql).
CREATE OR ALTER PROCEDURE dbo.usp_MonthlyReview_RecordDelivery
    @RunId          UNIQUEIDENTIFIER,
    @UserId         UNIQUEIDENTIFIER,
    @PeriodYear     SMALLINT,
    @PeriodMonth    TINYINT,
    @Status         NVARCHAR(20),
    @ErrorMessage   NVARCHAR(1000) = NULL,
    @GeneratedAtUtc DATETIME2(3)   = NULL,
    @EmailedAtUtc   DATETIME2(3)   = NULL,
    @DeliveryKind   NVARCHAR(20)   = N'Subscriber'
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.MonthlyReviewDeliveries
        (DeliveryId, RunId, UserId, PeriodYear, PeriodMonth, Status, ErrorMessage, GeneratedAtUtc, EmailedAtUtc, DeliveryKind)
    VALUES
        (NEWID(), @RunId, @UserId, @PeriodYear, @PeriodMonth, @Status, @ErrorMessage, @GeneratedAtUtc, @EmailedAtUtc, @DeliveryKind);
END
GO
