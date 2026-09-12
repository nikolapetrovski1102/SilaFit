USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.UserSettings', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserSettings
    (
        UserId                  UNIQUEIDENTIFIER NOT NULL,
        TargetWaterMl           INT              NOT NULL CONSTRAINT DF_UserSettings_TargetWaterMl DEFAULT (3500),
        NotificationsEnabled    BIT              NOT NULL CONSTRAINT DF_UserSettings_NotificationsEnabled DEFAULT (1),
        NotificationLocalTime   TIME(0)          NOT NULL CONSTRAINT DF_UserSettings_NotificationLocalTime DEFAULT ('18:00:00'),
        TimeZoneId              NVARCHAR(100)    NOT NULL CONSTRAINT DF_UserSettings_TimeZoneId DEFAULT ('UTC'),
        UpdatedAtUtc            DATETIME2(3)     NOT NULL CONSTRAINT DF_UserSettings_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_UserSettings PRIMARY KEY CLUSTERED (UserId),
        CONSTRAINT FK_UserSettings_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId)
    );
END
GO
