USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Users
    (
        UserId          UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Users_UserId DEFAULT NEWSEQUENTIALID(),
        DeviceId        NVARCHAR(200)    NULL,
        DisplayName     NVARCHAR(100)    NULL,
        Email           NVARCHAR(256)    NULL,
        PasswordHash    VARBINARY(256)   NULL,
        PasswordSalt    VARBINARY(128)   NULL,
        AccountTier     NVARCHAR(20)     NOT NULL CONSTRAINT DF_Users_AccountTier DEFAULT ('Guest'),
        CreatedAtUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_Users_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        LastLoginAtUtc  DATETIME2(3)     NULL,
        IsActive        BIT              NOT NULL CONSTRAINT DF_Users_IsActive DEFAULT (1),

        CONSTRAINT PK_Users PRIMARY KEY CLUSTERED (UserId),
        CONSTRAINT CK_Users_AccountTier CHECK (AccountTier IN ('Guest', 'Registered'))
    );

    CREATE UNIQUE INDEX UX_Users_DeviceId ON dbo.Users(DeviceId) WHERE DeviceId IS NOT NULL;
    CREATE UNIQUE INDEX UX_Users_Email ON dbo.Users(Email) WHERE Email IS NOT NULL;
END
GO
