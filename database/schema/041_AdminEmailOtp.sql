USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Optional recovery email for a console operator, plus the "send email code
-- instead" second factor: a short-lived numeric code emailed to that address as
-- an alternative to typing the authenticator app's TOTP code. Both codes are
-- accepted by the same POST /api/admin/auth/verify step (see AdminAuthService).
--
-- Email is deliberately optional (NULL for most operators, same as
-- dbo.Users.EmailVerifiedAtUtc for pre-existing accounts) - an operator with no
-- email on file simply never sees the "send email code instead" option.
IF COL_LENGTH('dbo.AdminUsers', 'Email') IS NULL
BEGIN
    ALTER TABLE dbo.AdminUsers ADD Email NVARCHAR(256) NULL;
END
GO

-- PBKDF2 hash/salt of the most recently emailed code, mirroring how the
-- password itself is stored - the plaintext code is never persisted. Cleared
-- (all four columns set back to NULL) the moment it is consumed by a
-- successful sign-in, so a code only ever verifies once.
IF COL_LENGTH('dbo.AdminUsers', 'EmailOtpCodeHash') IS NULL
BEGIN
    ALTER TABLE dbo.AdminUsers ADD EmailOtpCodeHash VARBINARY(256) NULL;
END
GO

IF COL_LENGTH('dbo.AdminUsers', 'EmailOtpCodeSalt') IS NULL
BEGIN
    ALTER TABLE dbo.AdminUsers ADD EmailOtpCodeSalt VARBINARY(128) NULL;
END
GO

IF COL_LENGTH('dbo.AdminUsers', 'EmailOtpExpiresAtUtc') IS NULL
BEGIN
    ALTER TABLE dbo.AdminUsers ADD EmailOtpExpiresAtUtc DATETIME2(3) NULL;
END
GO

-- Drives the resend cooldown (usp_Admin_SetEmailOtp), same idea as
-- PendingEmailVerifications.LastSentAtUtc.
IF COL_LENGTH('dbo.AdminUsers', 'EmailOtpLastSentAtUtc') IS NULL
BEGIN
    ALTER TABLE dbo.AdminUsers ADD EmailOtpLastSentAtUtc DATETIME2(3) NULL;
END
GO
