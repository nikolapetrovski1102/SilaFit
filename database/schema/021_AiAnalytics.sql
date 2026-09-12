USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- The "dedicated table for prompting": prompt text lives as data, not a C#
-- string literal, so the system/user prompt can be tuned without a deploy.
-- The user-prompt template contains {{Placeholder}} tokens the service layer
-- substitutes with a given user's real analytics numbers before calling the
-- AI - one row per TemplateKey; if more than one is ever marked active for
-- the same key, AnalyticsProvider takes the most recently updated.
IF OBJECT_ID(N'dbo.AiPromptTemplates', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AiPromptTemplates
    (
        PromptTemplateId    UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_AiPromptTemplates_Id DEFAULT NEWSEQUENTIALID(),
        TemplateKey         NVARCHAR(50)     NOT NULL,
        SystemPrompt        NVARCHAR(MAX)    NOT NULL,
        UserPromptTemplate  NVARCHAR(MAX)    NOT NULL,
        Model               NVARCHAR(100)    NOT NULL,
        IsActive            BIT              NOT NULL CONSTRAINT DF_AiPromptTemplates_IsActive DEFAULT (1),
        UpdatedAtUtc        DATETIME2(3)     NOT NULL CONSTRAINT DF_AiPromptTemplates_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_AiPromptTemplates PRIMARY KEY CLUSTERED (PromptTemplateId)
    );

    CREATE INDEX IX_AiPromptTemplates_TemplateKey_IsActive ON dbo.AiPromptTemplates(TemplateKey, IsActive);
END
GO

-- Cache/audit of every generated monthly report: SnapshotJson is the raw
-- numbers sent to the AI (audit/debugging), ResultJson is the AI's
-- structured JSON response stored verbatim so re-fetching the same month
-- never re-calls the (billed) AI.
IF OBJECT_ID(N'dbo.MonthlyAnalyticsReports', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MonthlyAnalyticsReports
    (
        ReportId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_MonthlyAnalyticsReports_Id DEFAULT NEWSEQUENTIALID(),
        UserId          UNIQUEIDENTIFIER NOT NULL,
        ReportYear      SMALLINT         NOT NULL,
        ReportMonth     TINYINT          NOT NULL,
        SnapshotJson    NVARCHAR(MAX)    NOT NULL,
        ResultJson      NVARCHAR(MAX)    NOT NULL,
        GeneratedAtUtc  DATETIME2(3)     NOT NULL CONSTRAINT DF_MonthlyAnalyticsReports_GeneratedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_MonthlyAnalyticsReports PRIMARY KEY CLUSTERED (ReportId),
        CONSTRAINT FK_MonthlyAnalyticsReports_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT UQ_MonthlyAnalyticsReports_UserId_Year_Month UNIQUE (UserId, ReportYear, ReportMonth),
        CONSTRAINT CK_MonthlyAnalyticsReports_ReportMonth CHECK (ReportMonth BETWEEN 1 AND 12)
    );
END
GO
