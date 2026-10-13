USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.HydrationLogs', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.HydrationLogs
    (
        HydrationLogId  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_HydrationLogs_Id DEFAULT NEWSEQUENTIALID(),
        UserId          UNIQUEIDENTIFIER NOT NULL,
        LoggedAtUtc     DATETIME2(3)     NOT NULL CONSTRAINT DF_HydrationLogs_LoggedAtUtc DEFAULT (SYSUTCDATETIME()),
        AmountMl        SMALLINT         NOT NULL,

        CONSTRAINT PK_HydrationLogs PRIMARY KEY CLUSTERED (HydrationLogId),
        CONSTRAINT FK_HydrationLogs_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT CK_HydrationLogs_AmountMl CHECK (AmountMl > 0)
    );

    CREATE INDEX IX_HydrationLogs_UserId_LoggedAtUtc ON dbo.HydrationLogs(UserId, LoggedAtUtc);
END
GO
