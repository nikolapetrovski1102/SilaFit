USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.BodyweightLogs', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BodyweightLogs
    (
        BodyweightLogId UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_BodyweightLogs_Id DEFAULT NEWSEQUENTIALID(),
        UserId          UNIQUEIDENTIFIER NOT NULL,
        LoggedAtUtc     DATETIME2(3)     NOT NULL CONSTRAINT DF_BodyweightLogs_LoggedAtUtc DEFAULT (SYSUTCDATETIME()),
        WeightKg        DECIMAL(5,2)     NOT NULL,

        CONSTRAINT PK_BodyweightLogs PRIMARY KEY CLUSTERED (BodyweightLogId),
        CONSTRAINT FK_BodyweightLogs_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT CK_BodyweightLogs_WeightKg CHECK (WeightKg > 0)
    );

    CREATE INDEX IX_BodyweightLogs_UserId_LoggedAtUtc ON dbo.BodyweightLogs(UserId, LoggedAtUtc);
END
GO
