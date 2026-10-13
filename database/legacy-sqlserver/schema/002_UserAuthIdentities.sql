USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- One row per linked provider identity (Device / Email / Google / Apple).
-- Lets a Guest account created via Device carry its history forward when
-- the user later links Email/Google/Apple, without changing UserId.
IF OBJECT_ID(N'dbo.UserAuthIdentities', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserAuthIdentities
    (
        AuthIdentityId  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_UserAuthIdentities_Id DEFAULT NEWSEQUENTIALID(),
        UserId          UNIQUEIDENTIFIER NOT NULL,
        Provider        NVARCHAR(20)     NOT NULL,
        ExternalId      NVARCHAR(256)    NOT NULL,
        CreatedAtUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_UserAuthIdentities_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_UserAuthIdentities PRIMARY KEY CLUSTERED (AuthIdentityId),
        CONSTRAINT FK_UserAuthIdentities_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT CK_UserAuthIdentities_Provider CHECK (Provider IN ('Device', 'Email', 'Google', 'Apple')),
        CONSTRAINT UQ_UserAuthIdentities_ProviderExternalId UNIQUE (Provider, ExternalId),
        CONSTRAINT UQ_UserAuthIdentities_UserProvider UNIQUE (UserId, Provider)
    );

    CREATE INDEX IX_UserAuthIdentities_UserId ON dbo.UserAuthIdentities(UserId);
END
GO
