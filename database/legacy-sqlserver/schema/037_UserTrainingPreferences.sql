USE SilenDb;
GO

-- Match the existing profile field encryption; null means not answered.
IF COL_LENGTH(N'dbo.UserProfiles', N'TrainingDaysPerWeek') IS NULL
    ALTER TABLE dbo.UserProfiles ADD TrainingDaysPerWeek VARBINARY(100) NULL;
GO
IF COL_LENGTH(N'dbo.UserProfiles', N'SessionDurationMinutes') IS NULL
    ALTER TABLE dbo.UserProfiles ADD SessionDurationMinutes VARBINARY(100) NULL;
GO
IF COL_LENGTH(N'dbo.UserProfiles', N'TrainingExperience') IS NULL
    ALTER TABLE dbo.UserProfiles ADD TrainingExperience VARBINARY(100) NULL;
GO
IF COL_LENGTH(N'dbo.UserProfiles', N'EquipmentAccess') IS NULL
    ALTER TABLE dbo.UserProfiles ADD EquipmentAccess VARBINARY(100) NULL;
GO
IF COL_LENGTH(N'dbo.UserProfiles', N'DailyActivityLevel') IS NULL
    ALTER TABLE dbo.UserProfiles ADD DailyActivityLevel VARBINARY(100) NULL;
GO
