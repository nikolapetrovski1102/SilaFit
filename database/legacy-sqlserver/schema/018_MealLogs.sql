USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.MealLogs', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MealLogs
    (
        MealLogId           UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_MealLogs_MealLogId DEFAULT (NEWSEQUENTIALID()),
        UserId               UNIQUEIDENTIFIER NOT NULL,
        LogDateUtc           DATE             NOT NULL,
        MealType             NVARCHAR(20)     NOT NULL CONSTRAINT CK_MealLogs_MealType CHECK (MealType IN ('Breakfast', 'Lunch', 'Dinner', 'Snack')),
        Title                NVARCHAR(200)    NOT NULL,
        CaloriesKcal         SMALLINT         NOT NULL,
        ProteinG             SMALLINT         NOT NULL,
        CarbsG               SMALLINT         NOT NULL,
        FatsG                SMALLINT         NOT NULL,
        Status               NVARCHAR(10)     NOT NULL CONSTRAINT DF_MealLogs_Status DEFAULT ('Planned') CONSTRAINT CK_MealLogs_Status CHECK (Status IN ('Planned', 'Logged')),
        PlannedLocalTime     TIME(0)          NULL,
        LoggedAtUtc          DATETIME2(3)     NULL,
        CreatedAtUtc         DATETIME2(3)     NOT NULL CONSTRAINT DF_MealLogs_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_MealLogs PRIMARY KEY CLUSTERED (MealLogId),
        CONSTRAINT FK_MealLogs_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId)
    );

    CREATE NONCLUSTERED INDEX IX_MealLogs_UserId_LogDateUtc ON dbo.MealLogs (UserId, LogDateUtc);
END
GO
