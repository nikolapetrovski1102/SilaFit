USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.SubscriptionPlans', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SubscriptionPlans
    (
        PlanId          UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_SubscriptionPlans_Id DEFAULT NEWSEQUENTIALID(),
        Code            NVARCHAR(30)     NOT NULL,
        Name            NVARCHAR(100)    NOT NULL,
        Tagline         NVARCHAR(300)    NULL,
        MonthlyPrice    DECIMAL(9,2)     NOT NULL,
        YearlyPrice     DECIMAL(9,2)     NOT NULL,
        IsFeatured      BIT              NOT NULL CONSTRAINT DF_SubscriptionPlans_IsFeatured DEFAULT (0),
        SortOrder       INT              NOT NULL CONSTRAINT DF_SubscriptionPlans_SortOrder DEFAULT (0),

        CONSTRAINT PK_SubscriptionPlans PRIMARY KEY CLUSTERED (PlanId),
        CONSTRAINT UQ_SubscriptionPlans_Code UNIQUE (Code)
    );
END
GO
