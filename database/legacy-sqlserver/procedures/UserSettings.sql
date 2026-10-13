USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserSettings_Get
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT UserId, TargetWaterMl, NotificationsEnabled, NotificationLocalTime, TimeZoneId,
           WeightUnit, DistanceUnit, RestTimerSoundEnabled, BarbellStandardKg, AppearanceMode,
           AvatarChoice, AiDataConsentAtUtc, UpdatedAtUtc
    FROM dbo.UserSettings
    WHERE UserId = @UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserSettings_SetNotificationsEnabled
    @UserId UNIQUEIDENTIFIER,
    @NotificationsEnabled BIT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.UserSettings
    SET NotificationsEnabled = @NotificationsEnabled,
        UpdatedAtUtc = SYSUTCDATETIME()
    WHERE UserId = @UserId;
END
GO

-- Grants (stamps now) or revokes (clears) consent to share the user's data
-- with the third-party AI provider. Kept out of usp_UserSettings_Update so a
-- plain settings save can never flip it by accident.
CREATE OR ALTER PROCEDURE dbo.usp_UserSettings_SetAiDataConsent
    @UserId UNIQUEIDENTIFIER,
    @Granted BIT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.UserSettings
    SET AiDataConsentAtUtc = CASE WHEN @Granted = 1 THEN COALESCE(AiDataConsentAtUtc, SYSUTCDATETIME()) ELSE NULL END,
        UpdatedAtUtc = SYSUTCDATETIME()
    WHERE UserId = @UserId;

    SELECT UserId, TargetWaterMl, NotificationsEnabled, NotificationLocalTime, TimeZoneId,
           WeightUnit, DistanceUnit, RestTimerSoundEnabled, BarbellStandardKg, AppearanceMode,
           AvatarChoice, AiDataConsentAtUtc, UpdatedAtUtc
    FROM dbo.UserSettings
    WHERE UserId = @UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserSettings_Update
    @UserId UNIQUEIDENTIFIER,
    @TargetWaterMl INT,
    @NotificationsEnabled BIT,
    @NotificationLocalTime TIME(0),
    @TimeZoneId NVARCHAR(100),
    @WeightUnit NVARCHAR(3),
    @DistanceUnit NVARCHAR(3),
    @RestTimerSoundEnabled BIT,
    @BarbellStandardKg DECIMAL(5, 2),
    @AppearanceMode NVARCHAR(10),
    @AvatarChoice NVARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.UserSettings
    SET TargetWaterMl = @TargetWaterMl,
        NotificationsEnabled = @NotificationsEnabled,
        NotificationLocalTime = @NotificationLocalTime,
        TimeZoneId = @TimeZoneId,
        WeightUnit = @WeightUnit,
        DistanceUnit = @DistanceUnit,
        RestTimerSoundEnabled = @RestTimerSoundEnabled,
        BarbellStandardKg = @BarbellStandardKg,
        AppearanceMode = @AppearanceMode,
        AvatarChoice = @AvatarChoice,
        UpdatedAtUtc = SYSUTCDATETIME()
    WHERE UserId = @UserId;

    SELECT UserId, TargetWaterMl, NotificationsEnabled, NotificationLocalTime, TimeZoneId,
           WeightUnit, DistanceUnit, RestTimerSoundEnabled, BarbellStandardKg, AppearanceMode,
           AvatarChoice, AiDataConsentAtUtc, UpdatedAtUtc
    FROM dbo.UserSettings
    WHERE UserId = @UserId;
END
GO
