USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Drives the "download my data" cooldown (usp_Account_TryBeginExport) so the
-- export flow - which decrypts and emails a user's full history as a JSON
-- attachment - can't be hammered to exfiltrate data or spam the mailbox.
-- NULL means the account has never requested an export.
IF COL_LENGTH('dbo.Users', 'LastExportRequestedAtUtc') IS NULL
BEGIN
    ALTER TABLE dbo.Users ADD LastExportRequestedAtUtc DATETIME2(3) NULL;
END
GO
