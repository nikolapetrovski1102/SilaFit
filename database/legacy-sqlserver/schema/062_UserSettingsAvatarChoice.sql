USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Lets a user override which default avatar silhouette (Male/Female) shows
-- in Settings, independent of the onboarding-collected gender it otherwise
-- falls back to on the client.
IF COL_LENGTH('dbo.UserSettings', 'AvatarChoice') IS NULL
BEGIN
    ALTER TABLE dbo.UserSettings
        ADD AvatarChoice NVARCHAR(10) NOT NULL CONSTRAINT DF_UserSettings_AvatarChoice DEFAULT ('Male')
            CONSTRAINT CK_UserSettings_AvatarChoice CHECK (AvatarChoice IN ('Male', 'Female'));
END
GO
