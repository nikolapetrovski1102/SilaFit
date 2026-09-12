USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Hydration_Log
    @UserId UNIQUEIDENTIFIER,
    @AmountMl SMALLINT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.HydrationLogs (UserId, AmountMl)
    VALUES (@UserId, @AmountMl);

    SELECT ISNULL(SUM(AmountMl), 0) AS TotalMlToday
    FROM dbo.HydrationLogs
    WHERE UserId = @UserId
      AND CAST(LoggedAtUtc AS DATE) = CAST(SYSUTCDATETIME() AS DATE);
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Hydration_GetToday
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ISNULL(SUM(AmountMl), 0) AS TotalMlToday
    FROM dbo.HydrationLogs
    WHERE UserId = @UserId
      AND CAST(LoggedAtUtc AS DATE) = CAST(SYSUTCDATETIME() AS DATE);
END
GO
