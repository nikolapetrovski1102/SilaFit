USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Set once email/password registration completes the verification-code step
-- - see usp_Auth_MarkEmailVerified. NULL for every pre-existing account and
-- for Google/Apple/Device logins, whose provider already vouches for the
-- address (or there is none).
IF COL_LENGTH('dbo.Users', 'EmailVerifiedAtUtc') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD EmailVerifiedAtUtc DATETIME2(3) NULL;
END
GO

-- Holds an in-progress email/password registration between
-- POST /auth/register/email/start and .../verify: the account itself isn't
-- created in dbo.Users until the emailed code is confirmed, so an abandoned
-- signup never leaves an unverified row behind. One row per email - starting
-- again for the same address replaces any row still unconsumed.
IF OBJECT_ID(N'dbo.PendingEmailVerifications', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.PendingEmailVerifications
    (
        PendingId       UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_PendingEmailVerifications PRIMARY KEY,
        ExistingUserId  UNIQUEIDENTIFIER NULL,
        Email           NVARCHAR(256)    NOT NULL,
        PasswordHash    VARBINARY(256)   NOT NULL,
        PasswordSalt    VARBINARY(128)   NOT NULL,
        DisplayName     NVARCHAR(100)    NULL,
        CodeHash        VARBINARY(256)   NOT NULL,
        CodeSalt        VARBINARY(128)   NOT NULL,
        AttemptCount    INT              NOT NULL CONSTRAINT DF_PendingEmailVerifications_AttemptCount DEFAULT (0),
        ExpiresAtUtc    DATETIME2(3)     NOT NULL,
        LastSentAtUtc   DATETIME2(3)     NOT NULL CONSTRAINT DF_PendingEmailVerifications_LastSentAtUtc DEFAULT (SYSUTCDATETIME()),
        CreatedAtUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_PendingEmailVerifications_CreatedAtUtc DEFAULT (SYSUTCDATETIME())
    );

    CREATE UNIQUE INDEX UX_PendingEmailVerifications_Email ON dbo.PendingEmailVerifications(Email);
END
GO
