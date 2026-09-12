USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.PlanFeatures', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.PlanFeatures
    (
        PlanFeatureId   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_PlanFeatures_Id DEFAULT NEWSEQUENTIALID(),
        PlanId          UNIQUEIDENTIFIER NOT NULL,
        FeatureText     NVARCHAR(300)    NOT NULL,
        SortOrder       TINYINT          NOT NULL CONSTRAINT DF_PlanFeatures_SortOrder DEFAULT (0),
        IsHighlighted   BIT              NOT NULL CONSTRAINT DF_PlanFeatures_IsHighlighted DEFAULT (0),

        CONSTRAINT PK_PlanFeatures PRIMARY KEY CLUSTERED (PlanFeatureId),
        CONSTRAINT FK_PlanFeatures_SubscriptionPlans FOREIGN KEY (PlanId) REFERENCES dbo.SubscriptionPlans(PlanId)
    );

    CREATE INDEX IX_PlanFeatures_PlanId ON dbo.PlanFeatures(PlanId);
END
GO
