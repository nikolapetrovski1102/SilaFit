USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserProfile_Get
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT UserId, Gender, AgeYears, HeightCm, WeightKg, Goal, TrainingDaysPerWeek, SessionDurationMinutes, TrainingExperience, EquipmentAccess, DailyActivityLevel, CreatedAtUtc, UpdatedAtUtc
    FROM dbo.UserProfiles
    WHERE UserId = @UserId;
END
GO

-- Gender/AgeYears/HeightCm/WeightKg/Goal are AES-256-GCM ciphertext
-- (Silen.Common.Helpers.FieldCipher) - encrypted/decrypted at the
-- UserProfileProvider layer, so these params are opaque VARBINARY here and
-- the CHECK constraints that used to validate Gender/Goal text now live in
-- UserProfileService.Validate() instead (see database/schema/025_ColumnEncryptionCutover.sql).
CREATE OR ALTER PROCEDURE dbo.usp_UserProfile_Upsert
    @UserId UNIQUEIDENTIFIER,
    @Gender VARBINARY(100),
    @AgeYears VARBINARY(100),
    @HeightCm VARBINARY(100),
    @WeightKg VARBINARY(100),
    @Goal VARBINARY(100),
    @TrainingDaysPerWeek VARBINARY(100) = NULL,
    @SessionDurationMinutes VARBINARY(100) = NULL,
    @TrainingExperience VARBINARY(100) = NULL,
    @EquipmentAccess VARBINARY(100) = NULL,
    @DailyActivityLevel VARBINARY(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.UserProfiles AS target
    USING (SELECT @UserId AS UserId) AS source
        ON target.UserId = source.UserId
    WHEN MATCHED THEN
        UPDATE SET
            Gender = @Gender,
            AgeYears = @AgeYears,
            HeightCm = @HeightCm,
            WeightKg = @WeightKg,
            Goal = @Goal,
            TrainingDaysPerWeek = COALESCE(@TrainingDaysPerWeek, target.TrainingDaysPerWeek),
            SessionDurationMinutes = COALESCE(@SessionDurationMinutes, target.SessionDurationMinutes),
            TrainingExperience = COALESCE(@TrainingExperience, target.TrainingExperience),
            EquipmentAccess = COALESCE(@EquipmentAccess, target.EquipmentAccess),
            DailyActivityLevel = COALESCE(@DailyActivityLevel, target.DailyActivityLevel),
            UpdatedAtUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (UserId, Gender, AgeYears, HeightCm, WeightKg, Goal, TrainingDaysPerWeek, SessionDurationMinutes, TrainingExperience, EquipmentAccess, DailyActivityLevel)
        VALUES (@UserId, @Gender, @AgeYears, @HeightCm, @WeightKg, @Goal, @TrainingDaysPerWeek, @SessionDurationMinutes, @TrainingExperience, @EquipmentAccess, @DailyActivityLevel);

    SELECT UserId, Gender, AgeYears, HeightCm, WeightKg, Goal, TrainingDaysPerWeek, SessionDurationMinutes, TrainingExperience, EquipmentAccess, DailyActivityLevel, CreatedAtUtc, UpdatedAtUtc
    FROM dbo.UserProfiles
    WHERE UserId = @UserId;
END
GO
