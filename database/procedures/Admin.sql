USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Console-operator auth for the static admin dashboard. Two stored procedures
-- here are also called by Silen.Tools.AdminProvision (enrollment/rotation), so
-- the provisioning path goes through exactly the same SQL as the runtime path.
--
-- See database/schema/027_AdminAccounts.sql for the tables.

-- Full row including credential material - only the login path and the
-- provisioning tool ever need the hash/salt/cipher.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_GetAccountByUsername
    @Username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    -- RoleId/RoleName ride along because the login path needs to know which
    -- permission set this operator will be resolved against (see AdminRbac.sql).
    SELECT u.AdminUserId, u.Username, u.PasswordHash, u.PasswordSalt, u.TotpSecretCipher,
           u.FailedAttemptCount, u.LockedUntilUtc, u.LastLoginAtUtc, u.PasswordChangedAtUtc,
           u.CreatedAtUtc, u.IsActive, u.RoleId, r.Name AS RoleName
    FROM dbo.AdminUsers u
    LEFT JOIN dbo.AdminRoles r ON r.RoleId = u.RoleId
    WHERE u.Username = @Username;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_GetAccountById
    @AdminUserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT u.AdminUserId, u.Username, u.PasswordHash, u.PasswordSalt, u.TotpSecretCipher,
           u.FailedAttemptCount, u.LockedUntilUtc, u.LastLoginAtUtc, u.PasswordChangedAtUtc,
           u.CreatedAtUtc, u.IsActive, u.RoleId, r.Name AS RoleName
    FROM dbo.AdminUsers u
    LEFT JOIN dbo.AdminRoles r ON r.RoleId = u.RoleId
    WHERE u.AdminUserId = @AdminUserId;
END
GO

-- Creates the account, or replaces its credentials when the username already
-- exists (that is what rotating means here). Either way it clears the lockout
-- counters and drops every existing session, so a rotation immediately logs any
-- other browser out instead of leaving it holding a pre-rotation session.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_UpsertAccount
    @Username NVARCHAR(100),
    @PasswordHash VARBINARY(256),
    @PasswordSalt VARBINARY(128),
    @TotpSecretCipher VARBINARY(256)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AdminUserId UNIQUEIDENTIFIER;

    BEGIN TRANSACTION;

    SELECT @AdminUserId = AdminUserId FROM dbo.AdminUsers WHERE Username = @Username;

    IF @AdminUserId IS NULL
    BEGIN
        SET @AdminUserId = NEWID();

        INSERT INTO dbo.AdminUsers (AdminUserId, Username, PasswordHash, PasswordSalt, TotpSecretCipher)
        VALUES (@AdminUserId, @Username, @PasswordHash, @PasswordSalt, @TotpSecretCipher);
    END
    ELSE
    BEGIN
        UPDATE dbo.AdminUsers
        SET PasswordHash = @PasswordHash,
            PasswordSalt = @PasswordSalt,
            TotpSecretCipher = @TotpSecretCipher,
            FailedAttemptCount = 0,
            LockedUntilUtc = NULL,
            PasswordChangedAtUtc = SYSUTCDATETIME(),
            IsActive = 1
        WHERE AdminUserId = @AdminUserId;

        DELETE FROM dbo.AdminSessions WHERE AdminUserId = @AdminUserId;
    END

    COMMIT TRANSACTION;

    SELECT @AdminUserId AS AdminUserId;
END
GO

-- Bumps the shared failure counter for both factors and locks the account once
-- @LockoutThreshold consecutive failures are reached. Returns the resulting
-- state so the caller can tell the user how long they're locked out for.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_RecordFailedLogin
    @AdminUserId UNIQUEIDENTIFIER,
    @LockoutThreshold INT,
    @LockoutMinutes INT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.AdminUsers
    SET FailedAttemptCount = FailedAttemptCount + 1,
        LockedUntilUtc = CASE
            WHEN FailedAttemptCount + 1 >= @LockoutThreshold
                THEN DATEADD(MINUTE, @LockoutMinutes, SYSUTCDATETIME())
            ELSE LockedUntilUtc
        END
    WHERE AdminUserId = @AdminUserId;

    SELECT FailedAttemptCount, LockedUntilUtc
    FROM dbo.AdminUsers
    WHERE AdminUserId = @AdminUserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_RecordSuccessfulLogin
    @AdminUserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.AdminUsers
    SET FailedAttemptCount = 0,
        LockedUntilUtc = NULL,
        LastLoginAtUtc = SYSUTCDATETIME()
    WHERE AdminUserId = @AdminUserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_CreateSession
    @AdminUserId UNIQUEIDENTIFIER,
    @TokenHash VARBINARY(32),
    @ExpiresAtUtc DATETIME2(3),
    @AbsoluteExpiresAtUtc DATETIME2(3),
    @CreatedFromIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AdminSessionId UNIQUEIDENTIFIER = NEWID();

    BEGIN TRANSACTION;

    -- Cheap housekeeping on the only path that creates rows.
    DELETE FROM dbo.AdminSessions
    WHERE AbsoluteExpiresAtUtc < SYSUTCDATETIME() OR ExpiresAtUtc < SYSUTCDATETIME();

    INSERT INTO dbo.AdminSessions (AdminSessionId, AdminUserId, TokenHash, ExpiresAtUtc, AbsoluteExpiresAtUtc, CreatedFromIp)
    VALUES (@AdminSessionId, @AdminUserId, @TokenHash, @ExpiresAtUtc, @AbsoluteExpiresAtUtc, @CreatedFromIp);

    COMMIT TRANSACTION;

    SELECT @AdminSessionId AS AdminSessionId;
END
GO

-- Resolves a cookie to a session. Returns no row when the session is unknown,
-- idle-expired, past its absolute ceiling, or the account has been deactivated -
-- all four are the same thing as far as the caller is concerned.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_GetSession
    @TokenHash VARBINARY(32)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.AdminSessionId, s.AdminUserId, s.ExpiresAtUtc, s.AbsoluteExpiresAtUtc,
           s.LastSeenAtUtc, u.Username
    FROM dbo.AdminSessions s
    INNER JOIN dbo.AdminUsers u ON u.AdminUserId = s.AdminUserId
    WHERE s.TokenHash = @TokenHash
      AND u.IsActive = 1
      AND s.ExpiresAtUtc > SYSUTCDATETIME()
      AND s.AbsoluteExpiresAtUtc > SYSUTCDATETIME();
END
GO

-- Slides the idle deadline. The absolute ceiling is enforced here rather than
-- in the caller so a stale client can't push it out by heartbeat.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_TouchSession
    @AdminSessionId UNIQUEIDENTIFIER,
    @ExpiresAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.AdminSessions
    SET LastSeenAtUtc = SYSUTCDATETIME(),
        ExpiresAtUtc = CASE
            WHEN @ExpiresAtUtc > AbsoluteExpiresAtUtc THEN AbsoluteExpiresAtUtc
            ELSE @ExpiresAtUtc
        END
    WHERE AdminSessionId = @AdminSessionId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_DeleteSession
    @TokenHash VARBINARY(32)
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.AdminSessions WHERE TokenHash = @TokenHash;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_DeleteAllSessions
    @AdminUserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.AdminSessions WHERE AdminUserId = @AdminUserId;
END
GO
