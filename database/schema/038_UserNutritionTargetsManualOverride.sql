USE SilenDb;
GO

-- Distinguishes targets the app derived from the user's profile (0, recomputed
-- whenever the profile changes) from targets the user set themselves via
-- PUT /api/meals/targets (1, left untouched). Existing rows predate the manual
-- override endpoint's tracking, so they default to auto-derived.
IF COL_LENGTH(N'dbo.UserNutritionTargets', N'IsManualOverride') IS NULL
    ALTER TABLE dbo.UserNutritionTargets
        ADD IsManualOverride BIT NOT NULL CONSTRAINT DF_UserNutritionTargets_IsManualOverride DEFAULT (0);
GO
