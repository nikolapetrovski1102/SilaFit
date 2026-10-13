USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.UserActiveSplits', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserActiveSplits
    (
        UserId          UNIQUEIDENTIFIER NOT NULL,
        SplitId         UNIQUEIDENTIFIER NOT NULL,
        ActivatedAtUtc  DATETIME2(3)     NOT NULL CONSTRAINT DF_UserActiveSplits_ActivatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_UserActiveSplits PRIMARY KEY CLUSTERED (UserId),
        CONSTRAINT FK_UserActiveSplits_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT FK_UserActiveSplits_WorkoutSplits FOREIGN KEY (SplitId) REFERENCES dbo.WorkoutSplits(SplitId)
    );
END
GO
