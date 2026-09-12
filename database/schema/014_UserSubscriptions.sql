USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- NOTE: Purchase here is a placeholder record keyed off the request the client
-- sends after a successful App Store / Play Store / payment-provider purchase.
-- Real receipt validation happens in that provider's SDK/webhook before this
-- table is written to; wiring that integration is a follow-up, not in scope here.
IF OBJECT_ID(N'dbo.UserSubscriptions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserSubscriptions
    (
        UserId          UNIQUEIDENTIFIER NOT NULL,
        PlanId          UNIQUEIDENTIFIER NOT NULL,
        BillingCycle    NVARCHAR(10)     NOT NULL,
        Status          NVARCHAR(20)     NOT NULL CONSTRAINT DF_UserSubscriptions_Status DEFAULT ('Active'),
        StartedAtUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_UserSubscriptions_StartedAtUtc DEFAULT (SYSUTCDATETIME()),
        ExpiresAtUtc    DATETIME2(3)     NULL,

        CONSTRAINT PK_UserSubscriptions PRIMARY KEY CLUSTERED (UserId),
        CONSTRAINT FK_UserSubscriptions_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT FK_UserSubscriptions_SubscriptionPlans FOREIGN KEY (PlanId) REFERENCES dbo.SubscriptionPlans(PlanId),
        CONSTRAINT CK_UserSubscriptions_BillingCycle CHECK (BillingCycle IN ('Monthly', 'Yearly')),
        CONSTRAINT CK_UserSubscriptions_Status CHECK (Status IN ('Active', 'Cancelled', 'Expired'))
    );
END
GO
