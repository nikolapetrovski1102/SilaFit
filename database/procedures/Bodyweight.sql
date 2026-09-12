USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- WeightKg is AES-256-GCM ciphertext (Silen.Common.Helpers.FieldCipher),
-- encrypted/decrypted at the BodyweightProvider layer - see
-- database/schema/025_ColumnEncryptionCutover.sql.

-- Returns the two most recent entries so the caller can compute the delta
-- without a second round-trip.
CREATE OR ALTER PROCEDURE dbo.usp_Bodyweight_Log
    @UserId UNIQUEIDENTIFIER,
    @WeightKg VARBINARY(64)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.BodyweightLogs (UserId, WeightKg)
    VALUES (@UserId, @WeightKg);

    SELECT TOP (2) BodyweightLogId, WeightKg, LoggedAtUtc
    FROM dbo.BodyweightLogs
    WHERE UserId = @UserId
    ORDER BY LoggedAtUtc DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Bodyweight_GetLatest
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (2) BodyweightLogId, WeightKg, LoggedAtUtc
    FROM dbo.BodyweightLogs
    WHERE UserId = @UserId
    ORDER BY LoggedAtUtc DESC;
END
GO

-- Feeds AnalyticsProvider's start/end-weight computation (moved out of
-- usp_Analytics_GetMonthlySnapshot since WeightKg is no longer readable in
-- T-SQL) - ordered ascending so the caller can take First()/Last().
CREATE OR ALTER PROCEDURE dbo.usp_Bodyweight_GetInRange
    @UserId UNIQUEIDENTIFIER,
    @FromDateUtc DATE,
    @ToDateUtc DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT BodyweightLogId, WeightKg, LoggedAtUtc
    FROM dbo.BodyweightLogs
    WHERE UserId = @UserId AND CAST(LoggedAtUtc AS DATE) BETWEEN @FromDateUtc AND @ToDateUtc
    ORDER BY LoggedAtUtc ASC;
END
GO
