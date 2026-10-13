USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- One-time cleanup of abandoned guest accounts: app installs that never signed
-- up, never logged a workout, meal, drink or weigh-in, and have not been back in
-- 7 days (see dbo.usp_Account_PruneOrphanGuests in procedures/Account.sql).
-- These are the "Unnamed user" rows in the admin console. Deletion is permanent.
--
-- Run the dry run first and check the list:
--   EXEC dbo.usp_Account_PruneOrphanGuests @IdleDays = 7, @DryRun = 1;
-- Take a backup, then run this file.

EXEC dbo.usp_Account_PruneOrphanGuests @IdleDays = 7, @DryRun = 0;
GO
