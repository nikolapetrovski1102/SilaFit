USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Plans_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    SELECT PlanId, Code, Name, Tagline, MonthlyPrice, YearlyPrice, IsFeatured, SortOrder
    FROM dbo.SubscriptionPlans
    ORDER BY SortOrder;

    SELECT PlanId, FeatureText, SortOrder, IsHighlighted
    FROM dbo.PlanFeatures
    ORDER BY PlanId, SortOrder;
END
GO

-- Placeholder purchase: records entitlement only. A real integration
-- validates the App Store / Play Store / payment-provider receipt server-side
-- before this proc is ever called.
CREATE OR ALTER PROCEDURE dbo.usp_Subscription_Purchase
    @UserId UNIQUEIDENTIFIER,
    @PlanId UNIQUEIDENTIFIER,
    @BillingCycle NVARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ExpiresAtUtc DATETIME2(3) = CASE WHEN @BillingCycle = 'Yearly'
        THEN DATEADD(YEAR, 1, SYSUTCDATETIME())
        ELSE DATEADD(MONTH, 1, SYSUTCDATETIME()) END;

    MERGE dbo.UserSubscriptions AS target
    USING (SELECT @UserId AS UserId) AS source
    ON target.UserId = source.UserId
    WHEN MATCHED THEN
        UPDATE SET PlanId = @PlanId, BillingCycle = @BillingCycle, Status = 'Active',
                   StartedAtUtc = SYSUTCDATETIME(), ExpiresAtUtc = @ExpiresAtUtc
    WHEN NOT MATCHED THEN
        INSERT (UserId, PlanId, BillingCycle, Status, StartedAtUtc, ExpiresAtUtc)
        VALUES (@UserId, @PlanId, @BillingCycle, 'Active', SYSUTCDATETIME(), @ExpiresAtUtc);

    SELECT UserId, PlanId, BillingCycle, Status, StartedAtUtc, ExpiresAtUtc
    FROM dbo.UserSubscriptions
    WHERE UserId = @UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Subscription_GetActive
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT us.UserId, us.PlanId, us.BillingCycle, us.Status, us.StartedAtUtc, us.ExpiresAtUtc, sp.Code, sp.Name
    FROM dbo.UserSubscriptions us
    INNER JOIN dbo.SubscriptionPlans sp ON sp.PlanId = us.PlanId
    WHERE us.UserId = @UserId;
END
GO
