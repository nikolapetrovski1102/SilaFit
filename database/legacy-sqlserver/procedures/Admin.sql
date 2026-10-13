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
    -- The EmailOtp* columns are the "send email code instead" second factor -
    -- see usp_Admin_SetEmailOtp. EmailConfirmedAtUtc gates that option on top of
    -- Email being non-null - see usp_Admin_Operator_ConfirmEmail.
    SELECT u.AdminUserId, u.Username, u.PasswordHash, u.PasswordSalt, u.TotpSecretCipher,
           u.FailedAttemptCount, u.LockedUntilUtc, u.LastLoginAtUtc, u.PasswordChangedAtUtc,
           u.CreatedAtUtc, u.IsActive, u.RoleId, r.Name AS RoleName,
           u.Email, u.EmailConfirmedAtUtc, u.EmailOtpCodeHash, u.EmailOtpCodeSalt, u.EmailOtpExpiresAtUtc, u.EmailOtpLastSentAtUtc
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
           u.CreatedAtUtc, u.IsActive, u.RoleId, r.Name AS RoleName,
           u.Email, u.EmailConfirmedAtUtc, u.EmailOtpCodeHash, u.EmailOtpCodeSalt, u.EmailOtpExpiresAtUtc, u.EmailOtpLastSentAtUtc
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
    @TotpSecretCipher VARBINARY(256),
    -- NULL means "leave whatever email is already on file alone" - the tool's
    -- --keep-totp-style default for a plain credential rotation. Pass an empty
    -- string to explicitly clear it.
    @Email NVARCHAR(256) = NULL
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

        INSERT INTO dbo.AdminUsers (AdminUserId, Username, PasswordHash, PasswordSalt, TotpSecretCipher, Email)
        VALUES (@AdminUserId, @Username, @PasswordHash, @PasswordSalt, @TotpSecretCipher, NULLIF(@Email, N''));
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
            IsActive = 1,
            Email = CASE WHEN @Email IS NULL THEN Email ELSE NULLIF(@Email, N'') END
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

-- Also burns the email-OTP fields whether or not this sign-in actually used
-- one, so a stale mailed code never verifies twice and a leftover row can't
-- outlive the session it belonged to.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_RecordSuccessfulLogin
    @AdminUserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.AdminUsers
    SET FailedAttemptCount = 0,
        LockedUntilUtc = NULL,
        LastLoginAtUtc = SYSUTCDATETIME(),
        EmailOtpCodeHash = NULL,
        EmailOtpCodeSalt = NULL,
        EmailOtpExpiresAtUtc = NULL,
        EmailOtpLastSentAtUtc = NULL
    WHERE AdminUserId = @AdminUserId;
END
GO

-- Sets the "send email code instead" second factor onto the row for the emailed
-- code AdminAuthService just generated. @Email is re-passed and checked rather
-- than trusted from an earlier read, so this can never silently write a code
-- for an account whose email was cleared between the two calls.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_SetEmailOtp
    @AdminUserId UNIQUEIDENTIFIER,
    @Email NVARCHAR(256),
    @CodeHash VARBINARY(256),
    @CodeSalt VARBINARY(128),
    @ExpiresAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.AdminUsers
    SET EmailOtpCodeHash = @CodeHash,
        EmailOtpCodeSalt = @CodeSalt,
        EmailOtpExpiresAtUtc = @ExpiresAtUtc,
        EmailOtpLastSentAtUtc = SYSUTCDATETIME()
    WHERE AdminUserId = @AdminUserId
      AND Email = @Email;
END
GO

-- Standalone email set/clear for the provisioning tool's --set-email, kept
-- separate from usp_Admin_UpsertAccount so an operator's recovery address can
-- be changed without rotating their password/TOTP secret or dropping sessions.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_SetEmail
    @AdminUserId UNIQUEIDENTIFIER,
    @Email NVARCHAR(256) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.AdminUsers
    SET Email = NULLIF(@Email, N'')
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
