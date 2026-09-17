USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Tags each split with the single UserProfiles.Goal value it best serves
-- (BuildMuscle / LoseFat / MaintainActive), so the Splits screen can surface
-- a "Recommended for you" pick using the goal collected during onboarding -
-- see Silen.Services.Implementations.SplitService, which must be kept in
-- sync with this CHECK.
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.WorkoutSplits') AND name = 'RecommendedGoal'
)
BEGIN
    ALTER TABLE dbo.WorkoutSplits ADD RecommendedGoal NVARCHAR(20) NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_WorkoutSplits_RecommendedGoal')
BEGIN
    ALTER TABLE dbo.WorkoutSplits
        ADD CONSTRAINT CK_WorkoutSplits_RecommendedGoal
        CHECK (RecommendedGoal IN ('BuildMuscle', 'LoseFat', 'MaintainActive') OR RecommendedGoal IS NULL);
END
GO

-- Widens the split-library taxonomy well beyond the original 4 categories
-- so the imported PHUL/PHAT/bro-split/circuit/powerlifting/calisthenics/
-- glute-focus protocols (see seed/001_SeedReferenceData.sql) are valid rows.
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_WorkoutSplits_Category')
BEGIN
    ALTER TABLE dbo.WorkoutSplits DROP CONSTRAINT CK_WorkoutSplits_Category;
END
GO

ALTER TABLE dbo.WorkoutSplits
    ADD CONSTRAINT CK_WorkoutSplits_Category CHECK (Category IN (
        'PushPullLegs', 'UpperLower', 'FullBody', 'ArnoldSplit',
        'PHUL', 'PHAT', 'BroSplit', 'Circuit', 'Powerlifting',
        'Calisthenics', 'GluteFocus', 'Custom'
    ));
GO
