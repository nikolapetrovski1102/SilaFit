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
-- The imported catalogue (006) only partially populated the column: many programs
-- whose source audience is a single gender arrived as the scraper's catch-all
-- 'Male & Female', so the onboarding gender answer had no effect on them and a
-- male could be auto-assigned e.g. "3 Day Full Body Toning Workout for Women".
-- Tagging here therefore *recomputes* the audience, not just fills NULLs, and
-- prefers the source categories (a real audience signal) over the name. Unisex
-- programs (categories name both genders, or neither) stay NULL / 'Male & Female'
-- and remain eligible to everyone. This stage runs after the imports, so it
-- reaches both fresh and already-seeded databases.

-- Source categories name one gender only: that is the program's audience.
UPDATE dbo.WorkoutSplits
SET TargetGender = N'Female'
WHERE TargetGender <> N'Female'
  AND SourceCategoriesJson LIKE N'%"Women"%'
  AND SourceCategoriesJson NOT LIKE N'%"Men"%';
GO

UPDATE dbo.WorkoutSplits
SET TargetGender = N'Male'
WHERE TargetGender <> N'Male'
  AND SourceCategoriesJson LIKE N'%"Men"%'
  AND SourceCategoriesJson NOT LIKE N'%"Women"%';
GO

-- Rows with no source categories fall back to the name/source-url cues that the
-- original tagging used. Guarded on the tag still being unset so a program whose
-- categories deliberately span both genders is not overridden by its name.
UPDATE dbo.WorkoutSplits
SET TargetGender = N'Female'
WHERE TargetGender IS NULL
  AND (SourceUrl IN (
        N'https://www.muscleandstrength.com/workouts/muscle-and-strength-womens-workout',
        N'https://www.muscleandstrength.com/workouts/muscle-and-strength-30-day-womens-workout')
       OR Name LIKE N'%Women%');
GO

-- The catalogue's only explicitly male-oriented program. Everything else in the
-- imported library is unisex and deliberately stays NULL so it remains eligible
-- to everyone; the gender-based category nudge in SplitRecommendationScorer is
-- what makes male/female picks differ for the rest of the library.
UPDATE dbo.WorkoutSplits
SET TargetGender = N'Male'
WHERE TargetGender IS NULL
  AND (SourceUrl = N'https://www.muscleandstrength.com/workouts/brandon-hendrickson-workout'
       OR Name LIKE N'%Men%Physique%');
GO
