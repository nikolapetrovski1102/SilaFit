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

    SELECT PlanId, Code, Name, Tagline, MonthlyPrice, YearlyPrice, IsFeatured, SortOrder,
           AppStoreMonthlyProductId, AppStoreYearlyProductId, PlayStoreMonthlyProductId, PlayStoreYearlyProductId
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

-- Every paying subscriber currently entitled to a given plan, with the
-- contact details the monthly review batch needs to reach them. "Active"
-- means the subscription row says so AND it has not lapsed - a row whose
-- ExpiresAtUtc has passed is treated as expired even before an expiry sweep
-- rewrites Status. Inactive (deleted/disabled) users are excluded.
CREATE OR ALTER PROCEDURE dbo.usp_Plans_GetActiveSubscribers
    @PlanCode NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        u.UserId,
        u.DisplayName,
        u.Email,
        sp.Code AS PlanCode,
        us.ExpiresAtUtc
    FROM dbo.UserSubscriptions us
    INNER JOIN dbo.SubscriptionPlans sp ON sp.PlanId = us.PlanId
    INNER JOIN dbo.Users u ON u.UserId = us.UserId
    WHERE sp.Code = @PlanCode
      AND us.Status = 'Active'
      AND u.IsActive = 1
      AND (us.ExpiresAtUtc IS NULL OR us.ExpiresAtUtc > SYSUTCDATETIME())
    ORDER BY u.CreatedAtUtc;
END
GO

-- The complement of usp_Plans_GetActiveSubscribers: active users with an email
-- on file who are NOT currently entitled to a paid plan. This is the audience
-- for the monthly review teaser (stats + upgrade CTA), not the full AI report.
--
-- "Paid" is the PRO/ADVANCED plan-code set the rest of the app gates on
-- (SubscriptionGate.ProPlanCodes); the FREE code is a catalogue row only, so
-- free users simply have no qualifying subscription row. Excluding by explicit
-- code list means a newly added paid tier must be added here too.
CREATE OR ALTER PROCEDURE dbo.usp_Plans_GetNonSubscribers
    @MaxUsers INT = 20000
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@MaxUsers)
        u.UserId,
        u.DisplayName,
        u.Email,
        N'FREE' AS PlanCode,
        CAST(NULL AS DATETIME2(3)) AS ExpiresAtUtc
    FROM dbo.Users u
    WHERE u.IsActive = 1
      AND u.Email IS NOT NULL
      AND LTRIM(RTRIM(u.Email)) <> N''
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.UserSubscriptions us
          INNER JOIN dbo.SubscriptionPlans sp ON sp.PlanId = us.PlanId
          WHERE us.UserId = u.UserId
            AND us.Status = 'Active'
            AND (us.ExpiresAtUtc IS NULL OR us.ExpiresAtUtc > SYSUTCDATETIME())
            AND sp.Code IN (N'PRO', N'ADVANCED')
      )
    ORDER BY u.CreatedAtUtc;
END
GO

-- The caller's current plan entitlements, if any. No row means either the
-- user has no active subscription (Free tier - the service layer supplies
-- hardcoded defaults for that case) or their plan has no PlanEntitlements
-- row yet.
CREATE OR ALTER PROCEDURE dbo.usp_Plans_GetEntitlementsForUser
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT pe.PlanId, pe.MaxActiveSplits, pe.MaxActiveDietPlans, pe.AllowAiGeneration
    FROM dbo.UserSubscriptions us
    INNER JOIN dbo.SubscriptionPlans sp ON sp.PlanId = us.PlanId
    INNER JOIN dbo.PlanEntitlements pe ON pe.PlanId = sp.PlanId
    WHERE us.UserId = @UserId
      AND us.Status = 'Active'
      AND (us.ExpiresAtUtc IS NULL OR us.ExpiresAtUtc > SYSUTCDATETIME());
END
GO
