USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.PlanEntitlements', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.PlanEntitlements
    (
        PlanId              UNIQUEIDENTIFIER NOT NULL,
        MaxActiveSplits     INT              NULL,
        MaxActiveDietPlans  INT              NULL,
        AllowAiGeneration   BIT              NOT NULL CONSTRAINT DF_PlanEntitlements_AllowAiGeneration DEFAULT (0),

        CONSTRAINT PK_PlanEntitlements PRIMARY KEY CLUSTERED (PlanId),
        CONSTRAINT FK_PlanEntitlements_SubscriptionPlans FOREIGN KEY (PlanId) REFERENCES dbo.SubscriptionPlans(PlanId)
    );
END
GO

-- Seed sane defaults for the existing paid tiers so subscribers aren't
-- suddenly unlimited-or-blocked the moment this ships; an admin can edit
-- these from the console afterwards.
IF NOT EXISTS (
    SELECT 1 FROM dbo.PlanEntitlements pe
    INNER JOIN dbo.SubscriptionPlans sp ON sp.PlanId = pe.PlanId
    WHERE sp.Code = N'PRO'
)
BEGIN
    INSERT INTO dbo.PlanEntitlements (PlanId, MaxActiveSplits, MaxActiveDietPlans, AllowAiGeneration)
    SELECT PlanId, 5, 5, 1
    FROM dbo.SubscriptionPlans
    WHERE Code = N'PRO';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM dbo.PlanEntitlements pe
    INNER JOIN dbo.SubscriptionPlans sp ON sp.PlanId = pe.PlanId
    WHERE sp.Code = N'ADVANCED'
)
BEGIN
    INSERT INTO dbo.PlanEntitlements (PlanId, MaxActiveSplits, MaxActiveDietPlans, AllowAiGeneration)
    SELECT PlanId, NULL, NULL, 1
    FROM dbo.SubscriptionPlans
    WHERE Code = N'ADVANCED';
END
GO
