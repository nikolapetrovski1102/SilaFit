USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Set once an operator clicks the link in their operator-creation confirmation
-- email (usp_Admin_Operator_ConfirmEmail). NULL for every pre-existing operator
-- and for any operator created without an email on file.
--
-- The "send email code instead" second factor (usp_Admin_SetEmailOtp /
-- AdminAuthService.SendEmailCodeAsync) now requires this to be set, not just
-- Email to be non-null - an address nobody has proven they control is not one
-- the console should be willing to email a second-factor code to.
IF COL_LENGTH('dbo.AdminUsers', 'EmailConfirmedAtUtc') IS NULL
BEGIN
    ALTER TABLE dbo.AdminUsers ADD EmailConfirmedAtUtc DATETIME2(3) NULL;
END
GO
