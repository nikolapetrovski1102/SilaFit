USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('dbo.UserSettings', 'WeightUnit') IS NULL
BEGIN
    ALTER TABLE dbo.UserSettings
        ADD WeightUnit NVARCHAR(3) NOT NULL CONSTRAINT DF_UserSettings_WeightUnit DEFAULT ('kg')
            CONSTRAINT CK_UserSettings_WeightUnit CHECK (WeightUnit IN ('kg', 'lb'));
END
GO

IF COL_LENGTH('dbo.UserSettings', 'DistanceUnit') IS NULL
BEGIN
    ALTER TABLE dbo.UserSettings
        ADD DistanceUnit NVARCHAR(3) NOT NULL CONSTRAINT DF_UserSettings_DistanceUnit DEFAULT ('km')
            CONSTRAINT CK_UserSettings_DistanceUnit CHECK (DistanceUnit IN ('km', 'mi'));
END
GO

IF COL_LENGTH('dbo.UserSettings', 'RestTimerSoundEnabled') IS NULL
BEGIN
    ALTER TABLE dbo.UserSettings
        ADD RestTimerSoundEnabled BIT NOT NULL CONSTRAINT DF_UserSettings_RestTimerSoundEnabled DEFAULT (1);
END
GO

IF COL_LENGTH('dbo.UserSettings', 'BarbellStandardKg') IS NULL
BEGIN
    ALTER TABLE dbo.UserSettings
        ADD BarbellStandardKg DECIMAL(5, 2) NOT NULL CONSTRAINT DF_UserSettings_BarbellStandardKg DEFAULT (20.00);
END
GO

IF COL_LENGTH('dbo.UserSettings', 'AppearanceMode') IS NULL
BEGIN
    ALTER TABLE dbo.UserSettings
        ADD AppearanceMode NVARCHAR(10) NOT NULL CONSTRAINT DF_UserSettings_AppearanceMode DEFAULT ('Dark')
            CONSTRAINT CK_UserSettings_AppearanceMode CHECK (AppearanceMode IN ('Dark', 'Light'));
END
GO
