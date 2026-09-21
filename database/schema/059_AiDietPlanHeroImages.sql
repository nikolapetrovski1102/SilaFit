USE SilenDb;
GO

-- NutritionPlans has filtered indexes, so SQL Server requires these SET
-- options on for any UPDATE that maintains them (including a one-time backfill).
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

-- AI diet plans created before goal-specific hero artwork was introduced have
-- no image. Give those existing rows the neutral weekly-meal image; subsequent
-- generations select goal-specific artwork in WeeklyPlanGenerationService.
UPDATE dbo.NutritionPlans
SET HeroImageUrl = N'https://images.sila.fitness/diet-plans/ai-weekly-general.png'
WHERE IsAiGenerated = 1
  AND NULLIF(LTRIM(RTRIM(HeroImageUrl)), N'') IS NULL;
GO
