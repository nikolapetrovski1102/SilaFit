USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- One row per AI food-photo scan (Advanced tier, meal tracker). Only the time
-- is kept - never the photo or what the AI said about it - because the table
-- exists to enforce the per-day scan allowance (usp_FoodScan_TryReserve). A
-- scan whose AI call fails is deleted again so an outage doesn't eat it.
IF OBJECT_ID(N'dbo.FoodScans', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FoodScans
    (
        FoodScanId      BIGINT IDENTITY(1,1) NOT NULL,
        UserId          UNIQUEIDENTIFIER     NOT NULL,
        ScannedAtUtc    DATETIME2(3)         NOT NULL CONSTRAINT DF_FoodScans_ScannedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_FoodScans PRIMARY KEY CLUSTERED (FoodScanId),
        CONSTRAINT FK_FoodScans_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId)
    );

    CREATE INDEX IX_FoodScans_User ON dbo.FoodScans(UserId, ScannedAtUtc);
END
GO
