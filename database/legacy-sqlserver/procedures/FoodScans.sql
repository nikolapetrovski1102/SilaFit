USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Claims one of today's AI food scans for @UserId, or reports that the
-- allowance is spent. "Today" is the user's local day, resolved by the caller
-- into @DayStartUtc. UPDLOCK + HOLDLOCK range-locks the user's rows for the
-- day, so two scans started at the same moment can't both read "2 used" and
-- both go through.
CREATE OR ALTER PROCEDURE dbo.usp_FoodScan_TryReserve
    @UserId      UNIQUEIDENTIFIER,
    @DayStartUtc DATETIME2(3),
    @DailyLimit  INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Used INT;

    BEGIN TRANSACTION;

    SELECT @Used = COUNT(*)
    FROM dbo.FoodScans WITH (UPDLOCK, HOLDLOCK)
    WHERE UserId = @UserId
      AND ScannedAtUtc >= @DayStartUtc;

    IF @Used >= @DailyLimit
    BEGIN
        COMMIT TRANSACTION;
        SELECT CAST(0 AS BIT) AS Allowed, @Used AS UsedToday, CAST(NULL AS BIGINT) AS FoodScanId;
        RETURN;
    END

    INSERT INTO dbo.FoodScans (UserId) VALUES (@UserId);
    DECLARE @FoodScanId BIGINT = SCOPE_IDENTITY();

    COMMIT TRANSACTION;

    SELECT CAST(1 AS BIT) AS Allowed, @Used + 1 AS UsedToday, @FoodScanId AS FoodScanId;
END
GO

-- Gives a reserved scan back - the AI call behind it failed, so it shouldn't
-- count against the day.
CREATE OR ALTER PROCEDURE dbo.usp_FoodScan_Release
    @UserId     UNIQUEIDENTIFIER,
    @FoodScanId BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.FoodScans
    WHERE FoodScanId = @FoodScanId
      AND UserId = @UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_FoodScan_CountSince
    @UserId      UNIQUEIDENTIFIER,
    @DayStartUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT COUNT(*) AS UsedToday
    FROM dbo.FoodScans
    WHERE UserId = @UserId
      AND ScannedAtUtc >= @DayStartUtc;
END
GO
