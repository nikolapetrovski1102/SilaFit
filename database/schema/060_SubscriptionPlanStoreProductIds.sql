USE SilenDb;
GO

-- Store product identifiers for real App Store / Play Store purchases. The
-- backend derives the granted plan from these verified IDs, never from a
-- client-claimed planId, so the seeded values here must match exactly what
-- gets created in App Store Connect / Play Console.
IF COL_LENGTH(N'dbo.SubscriptionPlans', N'AppStoreMonthlyProductId') IS NULL
    ALTER TABLE dbo.SubscriptionPlans ADD AppStoreMonthlyProductId NVARCHAR(150) NULL;
GO
IF COL_LENGTH(N'dbo.SubscriptionPlans', N'AppStoreYearlyProductId') IS NULL
    ALTER TABLE dbo.SubscriptionPlans ADD AppStoreYearlyProductId NVARCHAR(150) NULL;
GO
IF COL_LENGTH(N'dbo.SubscriptionPlans', N'PlayStoreMonthlyProductId') IS NULL
    ALTER TABLE dbo.SubscriptionPlans ADD PlayStoreMonthlyProductId NVARCHAR(150) NULL;
GO
IF COL_LENGTH(N'dbo.SubscriptionPlans', N'PlayStoreYearlyProductId') IS NULL
    ALTER TABLE dbo.SubscriptionPlans ADD PlayStoreYearlyProductId NVARCHAR(150) NULL;
GO

-- Re-runnable seed/correction, same style as 001_SeedReferenceData.sql's
-- price/tagline corrections: safe to run again if the IDs ever change.
--
-- Play Store IDs use a separate, shorter scheme (underscore-separated, no
-- reverse-DNS prefix) because Google Play caps product IDs at 40 characters -
-- the App Store-style "com.nikolapetrovski.silafit.advanced.monthly" is 44
-- characters and Play Console rejects it outright. Play product IDs don't
-- need to match the app's package name, so this is purely cosmetic.
UPDATE p
SET p.AppStoreMonthlyProductId = v.AppStoreMonthlyProductId,
    p.AppStoreYearlyProductId = v.AppStoreYearlyProductId,
    p.PlayStoreMonthlyProductId = v.PlayStoreMonthlyProductId,
    p.PlayStoreYearlyProductId = v.PlayStoreYearlyProductId
FROM dbo.SubscriptionPlans p
INNER JOIN (VALUES
    (N'PRO', N'com.nikolapetrovski.silafit.pro.monthly', N'com.nikolapetrovski.silafit.pro.yearly', N'silafit_pro_monthly', N'silafit_pro_yearly'),
    (N'ADVANCED', N'com.nikolapetrovski.silafit.advanced.monthly', N'com.nikolapetrovski.silafit.advanced.yearly', N'silafit_advanced_monthly', N'silafit_advanced_yearly')
) AS v(Code, AppStoreMonthlyProductId, AppStoreYearlyProductId, PlayStoreMonthlyProductId, PlayStoreYearlyProductId)
    ON v.Code = p.Code;
GO
