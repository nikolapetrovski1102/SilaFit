USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Cache/audit of every generated weekly (ADVANCED-only) report - the weekly
-- counterpart of dbo.MonthlyAnalyticsReports. SnapshotJson is the raw numbers
-- sent to the AI (audit/debugging), ResultJson is the AI's structured JSON
-- response stored verbatim so re-fetching the same ISO week never re-calls the
-- (billed) AI. ReportYear is the ISO week-numbering year, which can differ
-- from the calendar year around New Year - see ISOWeek in AnalyticsService.
IF OBJECT_ID(N'dbo.WeeklyAnalyticsReports', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.WeeklyAnalyticsReports
    (
        ReportId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_WeeklyAnalyticsReports_Id DEFAULT NEWSEQUENTIALID(),
        UserId          UNIQUEIDENTIFIER NOT NULL,
        ReportYear      SMALLINT         NOT NULL,
        ReportWeek      TINYINT          NOT NULL,
        SnapshotJson    NVARCHAR(MAX)    NOT NULL,
        ResultJson      NVARCHAR(MAX)    NOT NULL,
        GeneratedAtUtc  DATETIME2(3)     NOT NULL CONSTRAINT DF_WeeklyAnalyticsReports_GeneratedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_WeeklyAnalyticsReports PRIMARY KEY CLUSTERED (ReportId),
        CONSTRAINT FK_WeeklyAnalyticsReports_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT UQ_WeeklyAnalyticsReports_UserId_Year_Week UNIQUE (UserId, ReportYear, ReportWeek),
        CONSTRAINT CK_WeeklyAnalyticsReports_ReportWeek CHECK (ReportWeek BETWEEN 1 AND 53)
    );
END
GO
