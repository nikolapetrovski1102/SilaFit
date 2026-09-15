USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Distinguishes the two audiences the monthly review batch now serves:
--   Subscriber -> the full AI report emailed to a paying PRO/ADVANCED user
--   Upsell     -> the stats teaser + upgrade CTA emailed to a non-paying user
-- Kept as a delivery-level column (not just the run's PlanCode) because
-- idempotency is per audience: a free user who later upgrades during the same
-- period must still be able to receive the full report, and vice versa.
IF COL_LENGTH('dbo.MonthlyReviewDeliveries', 'DeliveryKind') IS NULL
BEGIN
    ALTER TABLE dbo.MonthlyReviewDeliveries
        ADD DeliveryKind NVARCHAR(20) NOT NULL
            CONSTRAINT DF_MonthlyReviewDeliveries_DeliveryKind DEFAULT (N'Subscriber');
END
GO

-- Guarded so a partially-applied migration can be re-run safely.
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_MonthlyReviewDeliveries_DeliveryKind')
BEGIN
    ALTER TABLE dbo.MonthlyReviewDeliveries WITH CHECK
        ADD CONSTRAINT CK_MonthlyReviewDeliveries_DeliveryKind
            CHECK (DeliveryKind IN (N'Subscriber', N'Upsell'));
END
GO

-- The "already emailed this period?" lookup filters on kind too, so index it
-- alongside the columns that lookup already uses.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MonthlyReviewDeliveries_Period_Kind_Status')
BEGIN
    CREATE INDEX IX_MonthlyReviewDeliveries_Period_Kind_Status
        ON dbo.MonthlyReviewDeliveries(PeriodYear, PeriodMonth, DeliveryKind, Status);
END
GO
