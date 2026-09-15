USE SilenDb;
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- The split recommender honors a program's source audience (WorkoutSplits.TargetGender):
-- a program tagged for one gender is never auto-activated for the other while a
-- unisex or matching option exists, and a matching program gets a ranking boost.
--
-- The imported catalogue (006) never populated the column, so the women-specific
-- programs shipped as unisex and the onboarding gender answer had no effect. This
-- seed stage runs after the imports, so tagging here reaches both fresh and
-- already-seeded databases. Unisex programs keep TargetGender NULL and stay
-- eligible to everyone.
UPDATE dbo.WorkoutSplits
SET TargetGender = N'Female'
WHERE TargetGender IS NULL
  AND (SourceUrl IN (
        N'https://www.muscleandstrength.com/workouts/muscle-and-strength-womens-workout',
        N'https://www.muscleandstrength.com/workouts/muscle-and-strength-30-day-womens-workout')
       OR Name LIKE N'%Women%');
GO
