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
           ReceiveWeeklyAiPlans, AutoActivateAiPlans, UpdatedAtUtc
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
    @ReceiveWeeklyAiPlans BIT = 0,
    @AutoActivateAiPlans BIT = 0
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
        ReceiveWeeklyAiPlans = @ReceiveWeeklyAiPlans,
        AutoActivateAiPlans = @AutoActivateAiPlans,
        UpdatedAtUtc = SYSUTCDATETIME()
    WHERE UserId = @UserId;

    SELECT UserId, TargetWaterMl, NotificationsEnabled, NotificationLocalTime, TimeZoneId,
           WeightUnit, DistanceUnit, RestTimerSoundEnabled, BarbellStandardKg, AppearanceMode,
           ReceiveWeeklyAiPlans, AutoActivateAiPlans, UpdatedAtUtc
    FROM dbo.UserSettings
    WHERE UserId = @UserId;
END
GO
