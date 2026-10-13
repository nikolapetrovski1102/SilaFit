USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.UserNutritionTargets', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserNutritionTargets
    (
        UserId          UNIQUEIDENTIFIER NOT NULL,
        TargetCalories  SMALLINT         NOT NULL,
        TargetProteinG  SMALLINT         NOT NULL,
        TargetCarbsG    SMALLINT         NOT NULL,
        TargetFatsG     SMALLINT         NOT NULL,
        UpdatedAtUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_UserNutritionTargets_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_UserNutritionTargets PRIMARY KEY CLUSTERED (UserId),
        CONSTRAINT FK_UserNutritionTargets_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId)
    );
END
GO
