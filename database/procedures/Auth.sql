USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Device (guest) login: creates the account on first call, otherwise just
-- touches LastLoginAtUtc and returns the existing row.
CREATE OR ALTER PROCEDURE dbo.usp_Auth_GetOrCreateDeviceUser
    @DeviceId NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @UserId UNIQUEIDENTIFIER;

    SELECT @UserId = UserId FROM dbo.Users WHERE DeviceId = @DeviceId;

    IF @UserId IS NULL
    BEGIN
        BEGIN TRANSACTION;

        SET @UserId = NEWID();

        INSERT INTO dbo.Users (UserId, DeviceId, AccountTier)
        VALUES (@UserId, @DeviceId, 'Guest');

        INSERT INTO dbo.UserAuthIdentities (UserId, Provider, ExternalId)
        VALUES (@UserId, 'Device', @DeviceId);

        INSERT INTO dbo.UserSettings (UserId)
        VALUES (@UserId);

        COMMIT TRANSACTION;
    END

    UPDATE dbo.Users SET LastLoginAtUtc = SYSUTCDATETIME() WHERE UserId = @UserId;

    SELECT UserId, DeviceId, DisplayName, Email, AccountTier, CreatedAtUtc, LastLoginAtUtc, IsActive
    FROM dbo.Users
    WHERE UserId = @UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Auth_GetUserByEmail
    @Email NVARCHAR(256)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT UserId, DeviceId, DisplayName, Email, PasswordHash, PasswordSalt, AccountTier, CreatedAtUtc, LastLoginAtUtc, IsActive
    FROM dbo.Users
    WHERE Email = @Email;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Auth_GetUserById
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT UserId, DeviceId, DisplayName, Email, AccountTier, CreatedAtUtc, LastLoginAtUtc, IsActive
    FROM dbo.Users
    WHERE UserId = @UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Auth_GetIdentity
    @Provider NVARCHAR(20),
    @ExternalId NVARCHAR(256)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT u.UserId, u.DeviceId, u.DisplayName, u.Email, u.AccountTier, u.CreatedAtUtc, u.LastLoginAtUtc, u.IsActive
    FROM dbo.UserAuthIdentities ai
    INNER JOIN dbo.Users u ON u.UserId = ai.UserId
    WHERE ai.Provider = @Provider AND ai.ExternalId = @ExternalId;
END
GO

-- Registers a brand-new email/password account when @UserId is NULL, or
-- upgrades an existing Guest (device) account to Registered when @UserId is
-- supplied, preserving that user's history (streaks, sessions, logs).
CREATE OR ALTER PROCEDURE dbo.usp_Auth_RegisterEmailUser
    @UserId UNIQUEIDENTIFIER = NULL,
    @Email NVARCHAR(256),
    @PasswordHash VARBINARY(256),
    @PasswordSalt VARBINARY(128),
    @DisplayName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    IF @UserId IS NOT NULL
    BEGIN
        UPDATE dbo.Users
        SET Email = @Email,
            PasswordHash = @PasswordHash,
            PasswordSalt = @PasswordSalt,
            DisplayName = COALESCE(DisplayName, @DisplayName),
            AccountTier = 'Registered'
        WHERE UserId = @UserId;
    END
    ELSE
    BEGIN
        SET @UserId = NEWID();

        INSERT INTO dbo.Users (UserId, Email, PasswordHash, PasswordSalt, DisplayName, AccountTier)
        VALUES (@UserId, @Email, @PasswordHash, @PasswordSalt, @DisplayName, 'Registered');

        INSERT INTO dbo.UserSettings (UserId)
        VALUES (@UserId);
    END

    INSERT INTO dbo.UserAuthIdentities (UserId, Provider, ExternalId)
    VALUES (@UserId, 'Email', @Email);

    COMMIT TRANSACTION;

    SELECT @UserId AS UserId;
END
GO

-- Signs in (or creates, or links to @UserId when a Guest is upgrading) via an
-- externally-verified Google/Apple identity. Token verification itself
-- happens in the API before this proc is ever called.
CREATE OR ALTER PROCEDURE dbo.usp_Auth_LinkExternalIdentity
    @UserId UNIQUEIDENTIFIER = NULL,
    @Provider NVARCHAR(20),
    @ExternalId NVARCHAR(256),
    @Email NVARCHAR(256) = NULL,
    @DisplayName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    IF @UserId IS NULL
    BEGIN
        SET @UserId = NEWID();

        INSERT INTO dbo.Users (UserId, Email, DisplayName, AccountTier)
        VALUES (@UserId, @Email, @DisplayName, 'Registered');

        INSERT INTO dbo.UserSettings (UserId)
        VALUES (@UserId);
    END
    ELSE
    BEGIN
        UPDATE dbo.Users
        SET Email = COALESCE(Email, @Email),
            DisplayName = COALESCE(DisplayName, @DisplayName),
            AccountTier = 'Registered'
        WHERE UserId = @UserId;
    END

    INSERT INTO dbo.UserAuthIdentities (UserId, Provider, ExternalId)
    VALUES (@UserId, @Provider, @ExternalId);

    COMMIT TRANSACTION;

    SELECT @UserId AS UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Auth_UpdateLastLogin
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Users SET LastLoginAtUtc = SYSUTCDATETIME() WHERE UserId = @UserId;
END
GO
