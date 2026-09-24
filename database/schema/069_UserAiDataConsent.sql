USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Records when a user agreed to have their workout, nutrition and profile
-- stats sent to the third-party AI provider (OpenRouter) behind AI reviews
-- and AI weekly plans. NULL = not granted (or revoked): no AI call may be
-- made with that user's data (App Review 5.1.1(i) / 5.1.2(i)).
IF COL_LENGTH('dbo.UserSettings', 'AiDataConsentAtUtc') IS NULL
BEGIN
    ALTER TABLE dbo.UserSettings
        ADD AiDataConsentAtUtc DATETIME2(0) NULL;
END
GO
