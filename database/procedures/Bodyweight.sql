USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Returns the two most recent entries so the caller can compute the delta
-- without a second round-trip.
CREATE OR ALTER PROCEDURE dbo.usp_Bodyweight_Log
    @UserId UNIQUEIDENTIFIER,
    @WeightKg DECIMAL(5,2)
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
