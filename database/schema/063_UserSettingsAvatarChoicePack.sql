USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Widens AvatarChoice (see 062_UserSettingsAvatarChoice.sql) from the
-- gender-only Male/Female pair to the full illustrated avatar pack: the two
-- plain gendered silhouettes stay as the default, plus 9 illustrated
-- character avatars per gender (see frontend/assets/avatars/male|female/ and
-- SettingsScreen's gender-gated avatar picker - male profiles only ever
-- choose from Male/Male1..Male9, female from Female/Female1..Female9).
-- Existing Male/Female rows stay valid as-is - this only adds new allowed
-- values, so no data backfill is needed.
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_UserSettings_AvatarChoice')
BEGIN
    ALTER TABLE dbo.UserSettings DROP CONSTRAINT CK_UserSettings_AvatarChoice;
END
GO

ALTER TABLE dbo.UserSettings
    ADD CONSTRAINT CK_UserSettings_AvatarChoice
        CHECK (AvatarChoice IN (
            'Male', 'Female',
            'Male1', 'Male2', 'Male3', 'Male4', 'Male5', 'Male6', 'Male7', 'Male8', 'Male9',
            'Female1', 'Female2', 'Female3', 'Female4', 'Female5', 'Female6', 'Female7', 'Female8', 'Female9'
        ));
GO
