USE SilenDb;
GO

-- Distinguishes a split the recommender picked for the user (1) from one the
-- user chose for themselves via POST /api/splits/activate (0). Lets
-- AutoAssignRecommendedAsync safely re-check the recommendation after later
-- onboarding answers without ever overriding a deliberate user choice.
-- Existing rows predate this tracking and default to a user pick (0), so no
-- currently-active split is silently re-shuffled by the new logic.
IF COL_LENGTH(N'dbo.UserActiveSplits', N'IsAutoAssigned') IS NULL
    ALTER TABLE dbo.UserActiveSplits
        ADD IsAutoAssigned BIT NOT NULL CONSTRAINT DF_UserActiveSplits_IsAutoAssigned DEFAULT (0);
GO
