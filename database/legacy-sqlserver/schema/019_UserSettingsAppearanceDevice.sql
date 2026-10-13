USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Adds 'Device' (follow the OS light/dark setting) as a third
-- AppearanceMode option alongside 'Dark'/'Light', and makes it the default
-- for newly-created rows - see Silen.Services.Implementations.SettingsService's
-- AppearanceModes list, which must be kept in sync with this CHECK.
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_UserSettings_AppearanceMode')
BEGIN
    ALTER TABLE dbo.UserSettings DROP CONSTRAINT CK_UserSettings_AppearanceMode;
END
GO

IF EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_UserSettings_AppearanceMode')
BEGIN
    ALTER TABLE dbo.UserSettings DROP CONSTRAINT DF_UserSettings_AppearanceMode;
END
GO

ALTER TABLE dbo.UserSettings
    ADD CONSTRAINT DF_UserSettings_AppearanceMode DEFAULT ('Device') FOR AppearanceMode;
GO

ALTER TABLE dbo.UserSettings
    ADD CONSTRAINT CK_UserSettings_AppearanceMode CHECK (AppearanceMode IN ('Dark', 'Light', 'Device'));
GO
