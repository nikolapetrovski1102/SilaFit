USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- One row per day of a diet plan, mirroring dbo.SplitDays.
IF OBJECT_ID(N'dbo.DietPlanDays', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DietPlanDays
    (
        DietPlanDayId UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_DietPlanDays_DietPlanDayId DEFAULT (NEWID()),
        DietPlanId    UNIQUEIDENTIFIER NOT NULL,
        DayIndex      TINYINT          NOT NULL,
        Title         NVARCHAR(200)    NULL,

        CONSTRAINT PK_DietPlanDays PRIMARY KEY CLUSTERED (DietPlanDayId),
        CONSTRAINT UQ_DietPlanDays_Plan_DayIndex UNIQUE (DietPlanId, DayIndex),
        CONSTRAINT CK_DietPlanDays_DayIndex CHECK (DayIndex BETWEEN 1 AND 31),
        CONSTRAINT FK_DietPlanDays_DietPlans FOREIGN KEY (DietPlanId)
            REFERENCES dbo.NutritionPlans(DietPlanId) ON DELETE CASCADE
    );

    CREATE INDEX IX_DietPlanDays_DietPlanId ON dbo.DietPlanDays(DietPlanId);
END
GO
