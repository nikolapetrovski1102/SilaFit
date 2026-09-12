USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Console operators for the static admin dashboard. Deliberately a separate
-- identity space from dbo.Users: an admin account is not a SilaFit user, has no
-- AccountTier, and never shows up in app queries.
--
-- Only ever holds a PBKDF2 hash/salt of the password (Silen.Common/Helpers/
-- PasswordHasher) and the AES-256-GCM-encrypted TOTP secret (FieldCipher), so a
-- database dump on its own yields neither the password nor the second factor.
IF OBJECT_ID(N'dbo.AdminUsers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AdminUsers
    (
        AdminUserId          UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_AdminUsers_AdminUserId DEFAULT NEWSEQUENTIALID(),
        Username             NVARCHAR(100)    NOT NULL,
        PasswordHash         VARBINARY(256)   NOT NULL,
        PasswordSalt         VARBINARY(128)   NOT NULL,
        -- FieldCipher output ([12-byte nonce][ciphertext][16-byte tag]) wrapping the
        -- base32 TOTP secret shown to the authenticator app at enrollment time.
        TotpSecretCipher     VARBINARY(256)   NOT NULL,
        -- Shared by both factors: a wrong password and a wrong code count the same way,
        -- which is what keeps a valid password from turning 6 digits into a
        -- brute-forceable space.
        FailedAttemptCount   INT              NOT NULL CONSTRAINT DF_AdminUsers_FailedAttemptCount DEFAULT (0),
        LockedUntilUtc       DATETIME2(3)     NULL,
        LastLoginAtUtc       DATETIME2(3)     NULL,
        PasswordChangedAtUtc DATETIME2(3)     NOT NULL CONSTRAINT DF_AdminUsers_PasswordChangedAtUtc DEFAULT (SYSUTCDATETIME()),
        CreatedAtUtc         DATETIME2(3)     NOT NULL CONSTRAINT DF_AdminUsers_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        IsActive             BIT              NOT NULL CONSTRAINT DF_AdminUsers_IsActive DEFAULT (1),

        CONSTRAINT PK_AdminUsers PRIMARY KEY CLUSTERED (AdminUserId)
    );

    CREATE UNIQUE INDEX UX_AdminUsers_Username ON dbo.AdminUsers(Username);
END
GO

-- One row per live console session. The browser holds the raw 32-byte token in
-- an HttpOnly cookie; only its SHA-256 is stored here, so this table is useless
-- to anyone who reads it without also having the cookies.
--
-- ExpiresAtUtc is the *idle* deadline (slid forward on every authenticated
-- request), AbsoluteExpiresAtUtc the hard ceiling that sliding can never pass -
-- so a session can't be kept alive forever by a tab left open.
IF OBJECT_ID(N'dbo.AdminSessions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AdminSessions
    (
        AdminSessionId       UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_AdminSessions_AdminSessionId DEFAULT NEWSEQUENTIALID(),
        AdminUserId          UNIQUEIDENTIFIER NOT NULL,
        TokenHash            VARBINARY(32)    NOT NULL,
        CreatedAtUtc         DATETIME2(3)     NOT NULL CONSTRAINT DF_AdminSessions_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        LastSeenAtUtc        DATETIME2(3)     NOT NULL CONSTRAINT DF_AdminSessions_LastSeenAtUtc DEFAULT (SYSUTCDATETIME()),
        ExpiresAtUtc         DATETIME2(3)     NOT NULL,
        AbsoluteExpiresAtUtc DATETIME2(3)     NOT NULL,
        CreatedFromIp        NVARCHAR(64)     NULL,

        CONSTRAINT PK_AdminSessions PRIMARY KEY CLUSTERED (AdminSessionId),
        CONSTRAINT FK_AdminSessions_AdminUsers FOREIGN KEY (AdminUserId) REFERENCES dbo.AdminUsers(AdminUserId)
    );

    CREATE UNIQUE INDEX UX_AdminSessions_TokenHash ON dbo.AdminSessions(TokenHash);
    CREATE INDEX IX_AdminSessions_AdminUserId ON dbo.AdminSessions(AdminUserId);
END
GO
