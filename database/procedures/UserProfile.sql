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

    SELECT UserId, Gender, AgeYears, HeightCm, WeightKg, Goal, CreatedAtUtc, UpdatedAtUtc
    FROM dbo.UserProfiles
    WHERE UserId = @UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserProfile_Upsert
    @UserId UNIQUEIDENTIFIER,
    @Gender NVARCHAR(10),
    @AgeYears TINYINT,
    @HeightCm DECIMAL(5, 1),
    @WeightKg DECIMAL(5, 1),
    @Goal NVARCHAR(20)
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
            UpdatedAtUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (UserId, Gender, AgeYears, HeightCm, WeightKg, Goal)
        VALUES (@UserId, @Gender, @AgeYears, @HeightCm, @WeightKg, @Goal);

    SELECT UserId, Gender, AgeYears, HeightCm, WeightKg, Goal, CreatedAtUtc, UpdatedAtUtc
    FROM dbo.UserProfiles
    WHERE UserId = @UserId;
END
GO
