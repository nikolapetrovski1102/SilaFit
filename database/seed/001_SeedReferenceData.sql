USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Idempotent reference-data seed: exercises, a default PPL split with its
-- days/exercises, and the subscription plan catalog shown on the Plans
-- screen. Safe to re-run.

----------------------------------------------------------------------------
-- Exercises
----------------------------------------------------------------------------
INSERT INTO dbo.Exercises (Name, MuscleGroup, EquipmentType, IsCompound)
SELECT v.Name, v.MuscleGroup, v.EquipmentType, v.IsCompound
FROM (VALUES
    (N'Incline Dumbbell Bench Press', N'chest', N'Dumbbell', 1),
    (N'Seated Dumbbell Overhead Press', N'shoulders', N'Dumbbell', 1),
    (N'Cable Standing Flyes', N'chest', N'Cable', 0),
    (N'Barbell Conventional Deadlift', N'back', N'Barbell', 1),
    (N'Wide-Grip Lat Pulldown', N'back', N'Cable', 1),
    (N'Incline Dumbbell Hammer Curl', N'arms', N'Dumbbell', 0),
    (N'Barbell High-Bar Back Squat', N'legs', N'Barbell', 1),
    (N'Romanian Deadlift (Dumbbells)', N'legs', N'Dumbbell', 1),
    (N'Seated Leg Extension', N'legs', N'Machine', 0),
    (N'Incline Barbell Bench Press', N'chest', N'Barbell', 1),
    (N'Chest-Supported T-Bar Row', N'back', N'Barbell', 1),
    (N'Bulgarian Split Squat', N'legs', N'Dumbbell', 0),
    (N'Cable Lateral Raise', N'shoulders', N'Cable', 0),
    (N'Overhead Rope Extension', N'arms', N'Cable', 0),
    (N'Barbell Hip Thrust', N'legs', N'Barbell', 1),
    (N'Cable Pull-Through', N'legs', N'Cable', 0),
    (N'Walking Lunge (Dumbbells)', N'legs', N'Dumbbell', 0),
    (N'Standing Calf Raise (Machine)', N'legs', N'Machine', 0),
    (N'Face Pull', N'shoulders', N'Cable', 0),
    (N'Barbell Front Squat', N'legs', N'Barbell', 1),
    (N'Push-Up', N'chest', N'Bodyweight', 1),
    (N'Pull-Up', N'back', N'Bodyweight', 1),
    (N'Bodyweight Dip', N'arms', N'Bodyweight', 1),
    (N'Bodyweight Squat', N'legs', N'Bodyweight', 1),
    (N'Plank Hold', N'core', N'Bodyweight', 0),
    (N'Hanging Leg Raise', N'core', N'Bodyweight', 0),
    (N'Close-Grip Bench Press', N'arms', N'Barbell', 1),
    (N'Barbell Bent-Over Row', N'back', N'Barbell', 1),
    (N'Seated Cable Row', N'back', N'Cable', 0),
    (N'Dumbbell Goblet Squat', N'legs', N'Dumbbell', 0),
    (N'Kettlebell Swing', N'legs', N'Kettlebell', 1),
    (N'Cable Crunch', N'core', N'Cable', 0),
    (N'Barbell Shrug', N'back', N'Barbell', 0),
    (N'Inverted Row (Bodyweight)', N'back', N'Bodyweight', 1),
    (N'Dumbbell Lateral Raise', N'shoulders', N'Dumbbell', 0),
    (N'Barbell Curl', N'arms', N'Barbell', 0)
) AS v(Name, MuscleGroup, EquipmentType, IsCompound)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Exercises e WHERE e.Name = v.Name);
GO

----------------------------------------------------------------------------
-- Workout splits (filter pills on the Splits screen)
----------------------------------------------------------------------------
INSERT INTO dbo.WorkoutSplits (Name, Category, Level, DurationDays, Description, IsSystemDefault, SortOrder, RecommendedGoal)
SELECT v.Name, v.Category, v.Level, v.DurationDays, v.Description, 1, v.SortOrder, v.RecommendedGoal
FROM (VALUES
    (N'PPL Hypertrophy Protocol', N'PushPullLegs', N'Intermediate', 6, N'High-volume push/pull/legs rotation for hypertrophy.', 1, N'BuildMuscle'),
    (N'Upper / Lower Split', N'UpperLower', N'Beginner', 4, N'Balanced 4-day upper/lower rotation.', 2, N'MaintainActive'),
    (N'Full Body Circuit', N'FullBody', N'Beginner', 3, N'3-day full body sessions for general strength.', 3, N'MaintainActive'),
    (N'Arnold Split', N'ArnoldSplit', N'Advanced', 6, N'Classic 6-day chest/back, shoulders/arms, legs rotation.', 4, N'BuildMuscle'),
    (N'PHUL Power Hypertrophy', N'PHUL', N'Intermediate', 4, N'4-day power/hypertrophy hybrid - heavy compounds early, volume work later in the week.', 5, N'BuildMuscle'),
    (N'PHAT Adaptive Training', N'PHAT', N'Advanced', 5, N'5-day power + hypertrophy split for advanced lifters chasing both strength and size.', 6, N'BuildMuscle'),
    (N'Classic Bro Split', N'BroSplit', N'Intermediate', 5, N'One body part per day - chest, back, shoulders, arms, legs.', 7, N'BuildMuscle'),
    (N'5-Day Metabolic Circuit', N'Circuit', N'Beginner', 5, N'High-rep, short-rest circuits across the whole body to maximize calorie burn.', 8, N'LoseFat'),
    (N'Lean & Lift Full Body', N'FullBody', N'Beginner', 3, N'3-day full body fat-loss protocol pairing compound lifts with higher-rep finishers.', 9, N'LoseFat'),
    (N'Glute & Core Sculpt', N'GluteFocus', N'Intermediate', 4, N'4-day lower-body-biased split emphasizing glutes, hamstrings, and core.', 10, N'LoseFat'),
    (N'Powerlifting Strength Block', N'Powerlifting', N'Advanced', 4, N'4-day squat/bench/deadlift-focused strength block with heavy top sets.', 11, N'BuildMuscle'),
    (N'Calisthenics Foundations', N'Calisthenics', N'Beginner', 3, N'3-day bodyweight-only program to build a strength base with no equipment.', 12, N'MaintainActive'),
    (N'2-Day Maintenance Full Body', N'FullBody', N'Beginner', 2, N'Minimal 2-day full body routine to stay active on a busy schedule.', 13, N'MaintainActive')
) AS v(Name, Category, Level, DurationDays, Description, SortOrder, RecommendedGoal)
WHERE NOT EXISTS (SELECT 1 FROM dbo.WorkoutSplits s WHERE s.Name = v.Name);
GO

-- Re-runnable goal tagging for the 4 original splits, in case this file was
-- already run (as INSERT ... WHERE NOT EXISTS) before RecommendedGoal existed.
UPDATE s
SET s.RecommendedGoal = v.RecommendedGoal
FROM dbo.WorkoutSplits s
INNER JOIN (VALUES
    (N'PPL Hypertrophy Protocol', N'BuildMuscle'),
    (N'Upper / Lower Split', N'MaintainActive'),
    (N'Full Body Circuit', N'MaintainActive'),
    (N'Arnold Split', N'BuildMuscle')
) AS v(Name, RecommendedGoal) ON v.Name = s.Name
WHERE s.RecommendedGoal IS NULL;
GO

-- Re-runnable correction: earlier versions of this file numbered SplitDays
-- from 0, but every save path (AdminConsoleService.SaveSplitDayAsync,
-- SplitService.SaveMySplitDayAsync, and the matching stored procedures)
-- rejects DayIndex < 1, so a split that still has a "Day 0" can be viewed
-- but never saved or managed from the admin dashboard. Shift any split that
-- still starts at 0 up by one so its numbering matches the 1-based VALUES
-- below - safe to re-run since a split only qualifies while MIN(DayIndex) = 0.
UPDATE sd
SET sd.DayIndex = sd.DayIndex + 1
FROM dbo.SplitDays sd
WHERE sd.SplitId IN (
    SELECT SplitId FROM dbo.SplitDays GROUP BY SplitId HAVING MIN(DayIndex) = 0
);
GO

----------------------------------------------------------------------------
-- Split days for PPL Hypertrophy Protocol
----------------------------------------------------------------------------
DECLARE @PplSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'PPL Hypertrophy Protocol');

INSERT INTO dbo.SplitDays (SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes)
SELECT @PplSplitId, v.DayIndex, v.Title, v.FocusLabel, v.EstimatedMinutes
FROM (VALUES
    (1, N'Push A: Chest, Delts & Triceps', N'Hypertrophy Focus', 45),
    (2, N'Pull A: Back & Biceps', N'Posterior Chain', 50),
    (3, N'Legs A: Quads & Calves', N'Quad Power & Calf', 55),
    (4, N'Push B: Chest, Delts & Triceps', N'Hypertrophy Focus', 45),
    (5, N'Pull B: Back & Biceps', N'Posterior Chain', 50),
    (6, N'Legs B: Quads & Calves', N'Quad Power & Calf', 55)
) AS v(DayIndex, Title, FocusLabel, EstimatedMinutes)
WHERE @PplSplitId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.SplitDays d WHERE d.SplitId = @PplSplitId AND d.DayIndex = v.DayIndex);
GO

----------------------------------------------------------------------------
-- Target exercises per PPL split day
----------------------------------------------------------------------------
DECLARE @PplSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'PPL Hypertrophy Protocol');

INSERT INTO dbo.SplitDayExercises (SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
SELECT sd.SplitDayId, e.ExerciseId, v.SortOrder, v.TargetSets, v.TargetRepsLow, v.TargetRepsHigh
FROM (VALUES
    (1, N'Incline Dumbbell Bench Press', 1, 4, 8, 10),
    (1, N'Seated Dumbbell Overhead Press', 2, 3, 10, 12),
    (1, N'Cable Standing Flyes', 3, 3, 12, 15),
    (2, N'Barbell Conventional Deadlift', 1, 4, 5, 6),
    (2, N'Wide-Grip Lat Pulldown', 2, 3, 10, 12),
    (2, N'Incline Dumbbell Hammer Curl', 3, 3, 12, 12),
    (3, N'Barbell High-Bar Back Squat', 1, 4, 6, 8),
    (3, N'Romanian Deadlift (Dumbbells)', 2, 3, 8, 10),
    (3, N'Seated Leg Extension', 3, 3, 12, 15),
    (4, N'Incline Dumbbell Bench Press', 1, 4, 8, 10),
    (4, N'Seated Dumbbell Overhead Press', 2, 3, 10, 12),
    (4, N'Cable Standing Flyes', 3, 3, 12, 15),
    (5, N'Barbell Conventional Deadlift', 1, 4, 5, 6),
    (5, N'Wide-Grip Lat Pulldown', 2, 3, 10, 12),
    (5, N'Incline Dumbbell Hammer Curl', 3, 3, 12, 12),
    (6, N'Barbell High-Bar Back Squat', 1, 4, 6, 8),
    (6, N'Romanian Deadlift (Dumbbells)', 2, 3, 8, 10),
    (6, N'Seated Leg Extension', 3, 3, 12, 15)
) AS v(DayIndex, ExerciseName, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
INNER JOIN dbo.SplitDays sd ON sd.SplitId = @PplSplitId AND sd.DayIndex = v.DayIndex
INNER JOIN dbo.Exercises e ON e.Name = v.ExerciseName
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.SplitDayExercises sde
    WHERE sde.SplitDayId = sd.SplitDayId AND sde.ExerciseId = e.ExerciseId
);
GO

----------------------------------------------------------------------------
-- Split days for Upper / Lower Split
----------------------------------------------------------------------------
DECLARE @UpperLowerSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Upper / Lower Split');

INSERT INTO dbo.SplitDays (SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes)
SELECT @UpperLowerSplitId, v.DayIndex, v.Title, v.FocusLabel, v.EstimatedMinutes
FROM (VALUES
    (1, N'Upper A: Chest, Back & Shoulders', N'Upper Body Strength', 50),
    (2, N'Lower A: Quads & Hamstrings', N'Lower Body Strength', 45),
    (3, N'Upper B: Chest, Back & Shoulders', N'Upper Body Hypertrophy', 50),
    (4, N'Lower B: Quads & Hamstrings', N'Lower Body Hypertrophy', 45)
) AS v(DayIndex, Title, FocusLabel, EstimatedMinutes)
WHERE @UpperLowerSplitId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.SplitDays d WHERE d.SplitId = @UpperLowerSplitId AND d.DayIndex = v.DayIndex);
GO

----------------------------------------------------------------------------
-- Target exercises per Upper/Lower split day
----------------------------------------------------------------------------
DECLARE @UpperLowerSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Upper / Lower Split');

INSERT INTO dbo.SplitDayExercises (SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
SELECT sd.SplitDayId, e.ExerciseId, v.SortOrder, v.TargetSets, v.TargetRepsLow, v.TargetRepsHigh
FROM (VALUES
    (1, N'Incline Barbell Bench Press', 1, 4, 6, 8),
    (1, N'Chest-Supported T-Bar Row', 2, 4, 8, 10),
    (1, N'Cable Lateral Raise', 3, 3, 12, 15),
    (2, N'Barbell High-Bar Back Squat', 1, 4, 6, 8),
    (2, N'Romanian Deadlift (Dumbbells)', 2, 3, 8, 10),
    (2, N'Bulgarian Split Squat', 3, 3, 10, 12),
    (3, N'Incline Dumbbell Bench Press', 1, 4, 8, 10),
    (3, N'Wide-Grip Lat Pulldown', 2, 4, 8, 10),
    (3, N'Overhead Rope Extension', 3, 3, 12, 15),
    (4, N'Barbell Conventional Deadlift', 1, 4, 5, 6),
    (4, N'Seated Leg Extension', 2, 3, 12, 15),
    (4, N'Bulgarian Split Squat', 3, 3, 10, 12)
) AS v(DayIndex, ExerciseName, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
INNER JOIN dbo.SplitDays sd ON sd.SplitId = @UpperLowerSplitId AND sd.DayIndex = v.DayIndex
INNER JOIN dbo.Exercises e ON e.Name = v.ExerciseName
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.SplitDayExercises sde
    WHERE sde.SplitDayId = sd.SplitDayId AND sde.ExerciseId = e.ExerciseId
);
GO

----------------------------------------------------------------------------
-- Split days for Full Body Circuit
----------------------------------------------------------------------------
DECLARE @FullBodySplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Full Body Circuit');

INSERT INTO dbo.SplitDays (SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes)
SELECT @FullBodySplitId, v.DayIndex, v.Title, v.FocusLabel, v.EstimatedMinutes
FROM (VALUES
    (1, N'Full Body A', N'General Strength', 40),
    (2, N'Full Body B', N'General Strength', 40),
    (3, N'Full Body C', N'General Strength', 40)
) AS v(DayIndex, Title, FocusLabel, EstimatedMinutes)
WHERE @FullBodySplitId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.SplitDays d WHERE d.SplitId = @FullBodySplitId AND d.DayIndex = v.DayIndex);
GO

----------------------------------------------------------------------------
-- Target exercises per Full Body split day
----------------------------------------------------------------------------
DECLARE @FullBodySplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Full Body Circuit');

INSERT INTO dbo.SplitDayExercises (SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
SELECT sd.SplitDayId, e.ExerciseId, v.SortOrder, v.TargetSets, v.TargetRepsLow, v.TargetRepsHigh
FROM (VALUES
    (1, N'Incline Dumbbell Bench Press', 1, 3, 8, 10),
    (1, N'Wide-Grip Lat Pulldown', 2, 3, 8, 10),
    (1, N'Barbell High-Bar Back Squat', 3, 3, 8, 10),
    (2, N'Seated Dumbbell Overhead Press', 1, 3, 10, 12),
    (2, N'Barbell Conventional Deadlift', 2, 3, 6, 8),
    (2, N'Bulgarian Split Squat', 3, 3, 10, 12),
    (3, N'Incline Barbell Bench Press', 1, 3, 8, 10),
    (3, N'Chest-Supported T-Bar Row', 2, 3, 8, 10),
    (3, N'Romanian Deadlift (Dumbbells)', 3, 3, 8, 10)
) AS v(DayIndex, ExerciseName, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
INNER JOIN dbo.SplitDays sd ON sd.SplitId = @FullBodySplitId AND sd.DayIndex = v.DayIndex
INNER JOIN dbo.Exercises e ON e.Name = v.ExerciseName
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.SplitDayExercises sde
    WHERE sde.SplitDayId = sd.SplitDayId AND sde.ExerciseId = e.ExerciseId
);
GO

----------------------------------------------------------------------------
-- Split days for Arnold Split
----------------------------------------------------------------------------
DECLARE @ArnoldSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Arnold Split');

INSERT INTO dbo.SplitDays (SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes)
SELECT @ArnoldSplitId, v.DayIndex, v.Title, v.FocusLabel, v.EstimatedMinutes
FROM (VALUES
    (1, N'Chest & Back A', N'Hypertrophy Focus', 55),
    (2, N'Shoulders & Arms A', N'Hypertrophy Focus', 45),
    (3, N'Legs A', N'Quad & Posterior Chain', 55),
    (4, N'Chest & Back B', N'Hypertrophy Focus', 55),
    (5, N'Shoulders & Arms B', N'Hypertrophy Focus', 45),
    (6, N'Legs B', N'Quad & Posterior Chain', 55)
) AS v(DayIndex, Title, FocusLabel, EstimatedMinutes)
WHERE @ArnoldSplitId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.SplitDays d WHERE d.SplitId = @ArnoldSplitId AND d.DayIndex = v.DayIndex);
GO

----------------------------------------------------------------------------
-- Target exercises per Arnold split day
----------------------------------------------------------------------------
DECLARE @ArnoldSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Arnold Split');

INSERT INTO dbo.SplitDayExercises (SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
SELECT sd.SplitDayId, e.ExerciseId, v.SortOrder, v.TargetSets, v.TargetRepsLow, v.TargetRepsHigh
FROM (VALUES
    (1, N'Incline Dumbbell Bench Press', 1, 4, 8, 10),
    (1, N'Chest-Supported T-Bar Row', 2, 4, 8, 10),
    (1, N'Cable Standing Flyes', 3, 3, 12, 15),
    (2, N'Seated Dumbbell Overhead Press', 1, 4, 8, 10),
    (2, N'Cable Lateral Raise', 2, 3, 12, 15),
    (2, N'Incline Dumbbell Hammer Curl', 3, 3, 10, 12),
    (3, N'Barbell High-Bar Back Squat', 1, 4, 6, 8),
    (3, N'Romanian Deadlift (Dumbbells)', 2, 3, 8, 10),
    (3, N'Seated Leg Extension', 3, 3, 12, 15),
    (4, N'Incline Barbell Bench Press', 1, 4, 6, 8),
    (4, N'Wide-Grip Lat Pulldown', 2, 4, 8, 10),
    (4, N'Cable Standing Flyes', 3, 3, 12, 15),
    (5, N'Seated Dumbbell Overhead Press', 1, 4, 8, 10),
    (5, N'Cable Lateral Raise', 2, 3, 12, 15),
    (5, N'Overhead Rope Extension', 3, 3, 12, 15),
    (6, N'Bulgarian Split Squat', 1, 3, 10, 12),
    (6, N'Barbell Conventional Deadlift', 2, 4, 5, 6),
    (6, N'Seated Leg Extension', 3, 3, 12, 15)
) AS v(DayIndex, ExerciseName, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
INNER JOIN dbo.SplitDays sd ON sd.SplitId = @ArnoldSplitId AND sd.DayIndex = v.DayIndex
INNER JOIN dbo.Exercises e ON e.Name = v.ExerciseName
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.SplitDayExercises sde
    WHERE sde.SplitDayId = sd.SplitDayId AND sde.ExerciseId = e.ExerciseId
);
GO

----------------------------------------------------------------------------
-- Split days for PHUL Power Hypertrophy
----------------------------------------------------------------------------
DECLARE @PhulSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'PHUL Power Hypertrophy');

INSERT INTO dbo.SplitDays (SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes)
SELECT @PhulSplitId, v.DayIndex, v.Title, v.FocusLabel, v.EstimatedMinutes
FROM (VALUES
    (1, N'Upper Power', N'Heavy Compounds', 55),
    (2, N'Lower Power', N'Heavy Compounds', 50),
    (3, N'Upper Hypertrophy', N'Volume Work', 55),
    (4, N'Lower Hypertrophy', N'Volume Work', 50)
) AS v(DayIndex, Title, FocusLabel, EstimatedMinutes)
WHERE @PhulSplitId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.SplitDays d WHERE d.SplitId = @PhulSplitId AND d.DayIndex = v.DayIndex);
GO

----------------------------------------------------------------------------
-- Target exercises per PHUL split day
----------------------------------------------------------------------------
DECLARE @PhulSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'PHUL Power Hypertrophy');

INSERT INTO dbo.SplitDayExercises (SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
SELECT sd.SplitDayId, e.ExerciseId, v.SortOrder, v.TargetSets, v.TargetRepsLow, v.TargetRepsHigh
FROM (VALUES
    (1, N'Incline Barbell Bench Press', 1, 3, 4, 6),
    (1, N'Barbell Bent-Over Row', 2, 3, 4, 6),
    (1, N'Seated Dumbbell Overhead Press', 3, 3, 6, 8),
    (1, N'Barbell Curl', 4, 3, 8, 10),
    (2, N'Barbell High-Bar Back Squat', 1, 4, 3, 5),
    (2, N'Barbell Conventional Deadlift', 2, 3, 3, 5),
    (2, N'Standing Calf Raise (Machine)', 3, 3, 10, 12),
    (3, N'Incline Dumbbell Bench Press', 1, 4, 8, 10),
    (3, N'Wide-Grip Lat Pulldown', 2, 4, 8, 10),
    (3, N'Cable Lateral Raise', 3, 3, 12, 15),
    (3, N'Close-Grip Bench Press', 4, 3, 10, 12),
    (3, N'Incline Dumbbell Hammer Curl', 5, 3, 10, 12),
    (4, N'Barbell Front Squat', 1, 4, 8, 10),
    (4, N'Romanian Deadlift (Dumbbells)', 2, 3, 10, 12),
    (4, N'Walking Lunge (Dumbbells)', 3, 3, 12, 12),
    (4, N'Seated Leg Extension', 4, 3, 12, 15)
) AS v(DayIndex, ExerciseName, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
INNER JOIN dbo.SplitDays sd ON sd.SplitId = @PhulSplitId AND sd.DayIndex = v.DayIndex
INNER JOIN dbo.Exercises e ON e.Name = v.ExerciseName
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.SplitDayExercises sde
    WHERE sde.SplitDayId = sd.SplitDayId AND sde.ExerciseId = e.ExerciseId
);
GO

----------------------------------------------------------------------------
-- Split days for PHAT Adaptive Training
----------------------------------------------------------------------------
DECLARE @PhatSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'PHAT Adaptive Training');

INSERT INTO dbo.SplitDays (SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes)
SELECT @PhatSplitId, v.DayIndex, v.Title, v.FocusLabel, v.EstimatedMinutes
FROM (VALUES
    (1, N'Upper Power', N'Heavy Compounds', 55),
    (2, N'Lower Power', N'Heavy Compounds', 50),
    (3, N'Back & Shoulders Hypertrophy', N'Volume Work', 55),
    (4, N'Chest & Arms Hypertrophy', N'Volume Work', 50),
    (5, N'Legs Hypertrophy', N'Volume Work', 55)
) AS v(DayIndex, Title, FocusLabel, EstimatedMinutes)
WHERE @PhatSplitId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.SplitDays d WHERE d.SplitId = @PhatSplitId AND d.DayIndex = v.DayIndex);
GO

----------------------------------------------------------------------------
-- Target exercises per PHAT split day
----------------------------------------------------------------------------
DECLARE @PhatSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'PHAT Adaptive Training');

INSERT INTO dbo.SplitDayExercises (SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
SELECT sd.SplitDayId, e.ExerciseId, v.SortOrder, v.TargetSets, v.TargetRepsLow, v.TargetRepsHigh
FROM (VALUES
    (1, N'Incline Barbell Bench Press', 1, 4, 3, 5),
    (1, N'Barbell Bent-Over Row', 2, 4, 3, 5),
    (1, N'Seated Dumbbell Overhead Press', 3, 3, 5, 6),
    (1, N'Barbell Curl', 4, 3, 6, 8),
    (2, N'Barbell High-Bar Back Squat', 1, 4, 3, 5),
    (2, N'Barbell Conventional Deadlift', 2, 3, 3, 5),
    (2, N'Standing Calf Raise (Machine)', 3, 3, 8, 10),
    (3, N'Wide-Grip Lat Pulldown', 1, 4, 8, 10),
    (3, N'Chest-Supported T-Bar Row', 2, 4, 8, 10),
    (3, N'Face Pull', 3, 3, 15, 15),
    (3, N'Cable Lateral Raise', 4, 3, 12, 15),
    (3, N'Barbell Shrug', 5, 3, 12, 12),
    (4, N'Incline Dumbbell Bench Press', 1, 4, 8, 10),
    (4, N'Cable Standing Flyes', 2, 3, 12, 15),
    (4, N'Close-Grip Bench Press', 3, 3, 10, 12),
    (4, N'Incline Dumbbell Hammer Curl', 4, 3, 10, 12),
    (4, N'Overhead Rope Extension', 5, 3, 12, 15),
    (5, N'Barbell Front Squat', 1, 4, 8, 10),
    (5, N'Romanian Deadlift (Dumbbells)', 2, 4, 10, 12),
    (5, N'Bulgarian Split Squat', 3, 3, 10, 12),
    (5, N'Seated Leg Extension', 4, 3, 15, 15),
    (5, N'Standing Calf Raise (Machine)', 5, 3, 15, 15)
) AS v(DayIndex, ExerciseName, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
INNER JOIN dbo.SplitDays sd ON sd.SplitId = @PhatSplitId AND sd.DayIndex = v.DayIndex
INNER JOIN dbo.Exercises e ON e.Name = v.ExerciseName
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.SplitDayExercises sde
    WHERE sde.SplitDayId = sd.SplitDayId AND sde.ExerciseId = e.ExerciseId
);
GO

----------------------------------------------------------------------------
-- Split days for Classic Bro Split
----------------------------------------------------------------------------
DECLARE @BroSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Classic Bro Split');

INSERT INTO dbo.SplitDays (SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes)
SELECT @BroSplitId, v.DayIndex, v.Title, v.FocusLabel, v.EstimatedMinutes
FROM (VALUES
    (1, N'Chest Day', N'Hypertrophy Focus', 50),
    (2, N'Back Day', N'Hypertrophy Focus', 50),
    (3, N'Shoulders Day', N'Hypertrophy Focus', 45),
    (4, N'Arms Day', N'Hypertrophy Focus', 45),
    (5, N'Legs Day', N'Hypertrophy Focus', 55)
) AS v(DayIndex, Title, FocusLabel, EstimatedMinutes)
WHERE @BroSplitId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.SplitDays d WHERE d.SplitId = @BroSplitId AND d.DayIndex = v.DayIndex);
GO

----------------------------------------------------------------------------
-- Target exercises per Bro split day
----------------------------------------------------------------------------
DECLARE @BroSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Classic Bro Split');

INSERT INTO dbo.SplitDayExercises (SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
SELECT sd.SplitDayId, e.ExerciseId, v.SortOrder, v.TargetSets, v.TargetRepsLow, v.TargetRepsHigh
FROM (VALUES
    (1, N'Incline Barbell Bench Press', 1, 4, 8, 10),
    (1, N'Incline Dumbbell Bench Press', 2, 3, 10, 12),
    (1, N'Cable Standing Flyes', 3, 3, 12, 15),
    (1, N'Push-Up', 4, 3, 12, 15),
    (2, N'Barbell Conventional Deadlift', 1, 4, 5, 6),
    (2, N'Wide-Grip Lat Pulldown', 2, 4, 8, 10),
    (2, N'Chest-Supported T-Bar Row', 3, 3, 8, 10),
    (2, N'Seated Cable Row', 4, 3, 10, 12),
    (3, N'Seated Dumbbell Overhead Press', 1, 4, 8, 10),
    (3, N'Cable Lateral Raise', 2, 3, 12, 15),
    (3, N'Dumbbell Lateral Raise', 3, 3, 12, 15),
    (3, N'Face Pull', 4, 3, 15, 15),
    (4, N'Close-Grip Bench Press', 1, 4, 8, 10),
    (4, N'Barbell Curl', 2, 4, 8, 10),
    (4, N'Incline Dumbbell Hammer Curl', 3, 3, 10, 12),
    (4, N'Overhead Rope Extension', 4, 3, 12, 15),
    (4, N'Bodyweight Dip', 5, 3, 10, 12),
    (5, N'Barbell High-Bar Back Squat', 1, 4, 6, 8),
    (5, N'Romanian Deadlift (Dumbbells)', 2, 3, 8, 10),
    (5, N'Bulgarian Split Squat', 3, 3, 10, 12),
    (5, N'Seated Leg Extension', 4, 3, 12, 15),
    (5, N'Standing Calf Raise (Machine)', 5, 4, 12, 15)
) AS v(DayIndex, ExerciseName, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
INNER JOIN dbo.SplitDays sd ON sd.SplitId = @BroSplitId AND sd.DayIndex = v.DayIndex
INNER JOIN dbo.Exercises e ON e.Name = v.ExerciseName
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.SplitDayExercises sde
    WHERE sde.SplitDayId = sd.SplitDayId AND sde.ExerciseId = e.ExerciseId
);
GO

----------------------------------------------------------------------------
-- Split days for 5-Day Metabolic Circuit
----------------------------------------------------------------------------
DECLARE @CircuitSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'5-Day Metabolic Circuit');

INSERT INTO dbo.SplitDays (SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes)
SELECT @CircuitSplitId, v.DayIndex, v.Title, v.FocusLabel, v.EstimatedMinutes
FROM (VALUES
    (1, N'Full Body Circuit A', N'Calorie Burn', 35),
    (2, N'Full Body Circuit B', N'Calorie Burn', 35),
    (3, N'Full Body Circuit C', N'Calorie Burn', 35),
    (4, N'Full Body Circuit D', N'Calorie Burn', 35),
    (5, N'Full Body Circuit E', N'Calorie Burn', 35)
) AS v(DayIndex, Title, FocusLabel, EstimatedMinutes)
WHERE @CircuitSplitId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.SplitDays d WHERE d.SplitId = @CircuitSplitId AND d.DayIndex = v.DayIndex);
GO

----------------------------------------------------------------------------
-- Target exercises per Metabolic Circuit split day
----------------------------------------------------------------------------
DECLARE @CircuitSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'5-Day Metabolic Circuit');

INSERT INTO dbo.SplitDayExercises (SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
SELECT sd.SplitDayId, e.ExerciseId, v.SortOrder, v.TargetSets, v.TargetRepsLow, v.TargetRepsHigh
FROM (VALUES
    (1, N'Kettlebell Swing', 1, 3, 15, 20),
    (1, N'Push-Up', 2, 3, 12, 15),
    (1, N'Dumbbell Goblet Squat', 3, 3, 15, 15),
    (1, N'Inverted Row (Bodyweight)', 4, 3, 12, 15),
    (1, N'Plank Hold', 5, 3, 30, 45),
    (2, N'Barbell Front Squat', 1, 3, 12, 15),
    (2, N'Seated Cable Row', 2, 3, 12, 15),
    (2, N'Walking Lunge (Dumbbells)', 3, 3, 12, 12),
    (2, N'Cable Crunch', 4, 3, 15, 20),
    (3, N'Kettlebell Swing', 1, 3, 15, 20),
    (3, N'Bodyweight Dip', 2, 3, 10, 12),
    (3, N'Cable Pull-Through', 3, 3, 15, 15),
    (3, N'Hanging Leg Raise', 4, 3, 10, 12),
    (4, N'Dumbbell Goblet Squat', 1, 3, 15, 15),
    (4, N'Pull-Up', 2, 3, 8, 10),
    (4, N'Barbell Hip Thrust', 3, 3, 12, 15),
    (4, N'Plank Hold', 4, 3, 30, 45),
    (5, N'Push-Up', 1, 3, 15, 15),
    (5, N'Kettlebell Swing', 2, 3, 20, 20),
    (5, N'Walking Lunge (Dumbbells)', 3, 3, 12, 12),
    (5, N'Cable Crunch', 4, 3, 20, 20)
) AS v(DayIndex, ExerciseName, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
INNER JOIN dbo.SplitDays sd ON sd.SplitId = @CircuitSplitId AND sd.DayIndex = v.DayIndex
INNER JOIN dbo.Exercises e ON e.Name = v.ExerciseName
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.SplitDayExercises sde
    WHERE sde.SplitDayId = sd.SplitDayId AND sde.ExerciseId = e.ExerciseId
);
GO

----------------------------------------------------------------------------
-- Split days for Lean & Lift Full Body
----------------------------------------------------------------------------
DECLARE @LeanFullBodySplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Lean & Lift Full Body');

INSERT INTO dbo.SplitDays (SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes)
SELECT @LeanFullBodySplitId, v.DayIndex, v.Title, v.FocusLabel, v.EstimatedMinutes
FROM (VALUES
    (1, N'Full Body A', N'Fat Loss', 40),
    (2, N'Full Body B', N'Fat Loss', 40),
    (3, N'Full Body C', N'Fat Loss', 40)
) AS v(DayIndex, Title, FocusLabel, EstimatedMinutes)
WHERE @LeanFullBodySplitId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.SplitDays d WHERE d.SplitId = @LeanFullBodySplitId AND d.DayIndex = v.DayIndex);
GO

----------------------------------------------------------------------------
-- Target exercises per Lean & Lift Full Body split day
----------------------------------------------------------------------------
DECLARE @LeanFullBodySplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Lean & Lift Full Body');

INSERT INTO dbo.SplitDayExercises (SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
SELECT sd.SplitDayId, e.ExerciseId, v.SortOrder, v.TargetSets, v.TargetRepsLow, v.TargetRepsHigh
FROM (VALUES
    (1, N'Barbell High-Bar Back Squat', 1, 3, 8, 10),
    (1, N'Incline Dumbbell Bench Press', 2, 3, 10, 12),
    (1, N'Seated Cable Row', 3, 3, 12, 15),
    (1, N'Cable Crunch', 4, 3, 15, 20),
    (2, N'Romanian Deadlift (Dumbbells)', 1, 3, 10, 12),
    (2, N'Push-Up', 2, 3, 12, 15),
    (2, N'Wide-Grip Lat Pulldown', 3, 3, 10, 12),
    (2, N'Plank Hold', 4, 3, 30, 45),
    (3, N'Dumbbell Goblet Squat', 1, 3, 12, 15),
    (3, N'Seated Dumbbell Overhead Press', 2, 3, 10, 12),
    (3, N'Inverted Row (Bodyweight)', 3, 3, 10, 12),
    (3, N'Kettlebell Swing', 4, 3, 15, 20)
) AS v(DayIndex, ExerciseName, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
INNER JOIN dbo.SplitDays sd ON sd.SplitId = @LeanFullBodySplitId AND sd.DayIndex = v.DayIndex
INNER JOIN dbo.Exercises e ON e.Name = v.ExerciseName
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.SplitDayExercises sde
    WHERE sde.SplitDayId = sd.SplitDayId AND sde.ExerciseId = e.ExerciseId
);
GO

----------------------------------------------------------------------------
-- Split days for Glute & Core Sculpt
----------------------------------------------------------------------------
DECLARE @GluteSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Glute & Core Sculpt');

INSERT INTO dbo.SplitDays (SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes)
SELECT @GluteSplitId, v.DayIndex, v.Title, v.FocusLabel, v.EstimatedMinutes
FROM (VALUES
    (1, N'Glutes & Hamstrings A', N'Lower Body Focus', 45),
    (2, N'Core & Conditioning', N'Calorie Burn', 35),
    (3, N'Glutes & Hamstrings B', N'Lower Body Focus', 45),
    (4, N'Lower Body & Core Finisher', N'Calorie Burn', 40)
) AS v(DayIndex, Title, FocusLabel, EstimatedMinutes)
WHERE @GluteSplitId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.SplitDays d WHERE d.SplitId = @GluteSplitId AND d.DayIndex = v.DayIndex);
GO

----------------------------------------------------------------------------
-- Target exercises per Glute & Core Sculpt split day
----------------------------------------------------------------------------
DECLARE @GluteSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Glute & Core Sculpt');

INSERT INTO dbo.SplitDayExercises (SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
SELECT sd.SplitDayId, e.ExerciseId, v.SortOrder, v.TargetSets, v.TargetRepsLow, v.TargetRepsHigh
FROM (VALUES
    (1, N'Barbell Hip Thrust', 1, 4, 10, 12),
    (1, N'Romanian Deadlift (Dumbbells)', 2, 4, 10, 12),
    (1, N'Cable Pull-Through', 3, 3, 12, 15),
    (1, N'Plank Hold', 4, 3, 30, 45),
    (2, N'Hanging Leg Raise', 1, 3, 12, 15),
    (2, N'Cable Crunch', 2, 3, 15, 20),
    (2, N'Kettlebell Swing', 3, 3, 15, 20),
    (2, N'Plank Hold', 4, 3, 45, 45),
    (3, N'Barbell Hip Thrust', 1, 4, 12, 15),
    (3, N'Bulgarian Split Squat', 2, 3, 10, 12),
    (3, N'Walking Lunge (Dumbbells)', 3, 3, 12, 12),
    (3, N'Standing Calf Raise (Machine)', 4, 3, 15, 15),
    (4, N'Dumbbell Goblet Squat', 1, 3, 12, 15),
    (4, N'Cable Pull-Through', 2, 3, 15, 15),
    (4, N'Hanging Leg Raise', 3, 3, 12, 15),
    (4, N'Cable Crunch', 4, 3, 20, 20)
) AS v(DayIndex, ExerciseName, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
INNER JOIN dbo.SplitDays sd ON sd.SplitId = @GluteSplitId AND sd.DayIndex = v.DayIndex
INNER JOIN dbo.Exercises e ON e.Name = v.ExerciseName
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.SplitDayExercises sde
    WHERE sde.SplitDayId = sd.SplitDayId AND sde.ExerciseId = e.ExerciseId
);
GO

----------------------------------------------------------------------------
-- Split days for Powerlifting Strength Block
----------------------------------------------------------------------------
DECLARE @PowerliftingSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Powerlifting Strength Block');

INSERT INTO dbo.SplitDays (SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes)
SELECT @PowerliftingSplitId, v.DayIndex, v.Title, v.FocusLabel, v.EstimatedMinutes
FROM (VALUES
    (1, N'Squat Day', N'Max Strength', 60),
    (2, N'Bench Day', N'Max Strength', 55),
    (3, N'Deadlift Day', N'Max Strength', 60),
    (4, N'Accessory & Weak Point Day', N'Supplemental Strength', 50)
) AS v(DayIndex, Title, FocusLabel, EstimatedMinutes)
WHERE @PowerliftingSplitId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.SplitDays d WHERE d.SplitId = @PowerliftingSplitId AND d.DayIndex = v.DayIndex);
GO

----------------------------------------------------------------------------
-- Target exercises per Powerlifting split day
----------------------------------------------------------------------------
DECLARE @PowerliftingSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Powerlifting Strength Block');

INSERT INTO dbo.SplitDayExercises (SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
SELECT sd.SplitDayId, e.ExerciseId, v.SortOrder, v.TargetSets, v.TargetRepsLow, v.TargetRepsHigh
FROM (VALUES
    (1, N'Barbell High-Bar Back Squat', 1, 5, 3, 5),
    (1, N'Barbell Front Squat', 2, 3, 5, 5),
    (1, N'Seated Leg Extension', 3, 3, 10, 12),
    (2, N'Incline Barbell Bench Press', 1, 5, 3, 5),
    (2, N'Close-Grip Bench Press', 2, 3, 5, 6),
    (2, N'Cable Standing Flyes', 3, 3, 10, 12),
    (3, N'Barbell Conventional Deadlift', 1, 5, 3, 5),
    (3, N'Barbell Bent-Over Row', 2, 3, 5, 6),
    (3, N'Barbell Shrug', 3, 3, 8, 10),
    (4, N'Bulgarian Split Squat', 1, 3, 8, 10),
    (4, N'Seated Dumbbell Overhead Press', 2, 3, 6, 8),
    (4, N'Wide-Grip Lat Pulldown', 3, 3, 8, 10),
    (4, N'Barbell Curl', 4, 3, 8, 10)
) AS v(DayIndex, ExerciseName, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
INNER JOIN dbo.SplitDays sd ON sd.SplitId = @PowerliftingSplitId AND sd.DayIndex = v.DayIndex
INNER JOIN dbo.Exercises e ON e.Name = v.ExerciseName
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.SplitDayExercises sde
    WHERE sde.SplitDayId = sd.SplitDayId AND sde.ExerciseId = e.ExerciseId
);
GO

----------------------------------------------------------------------------
-- Split days for Calisthenics Foundations
----------------------------------------------------------------------------
DECLARE @CalisthenicsSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Calisthenics Foundations');

INSERT INTO dbo.SplitDays (SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes)
SELECT @CalisthenicsSplitId, v.DayIndex, v.Title, v.FocusLabel, v.EstimatedMinutes
FROM (VALUES
    (1, N'Push Foundations', N'Bodyweight Strength', 35),
    (2, N'Pull Foundations', N'Bodyweight Strength', 35),
    (3, N'Legs & Core Foundations', N'Bodyweight Strength', 35)
) AS v(DayIndex, Title, FocusLabel, EstimatedMinutes)
WHERE @CalisthenicsSplitId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.SplitDays d WHERE d.SplitId = @CalisthenicsSplitId AND d.DayIndex = v.DayIndex);
GO

----------------------------------------------------------------------------
-- Target exercises per Calisthenics Foundations split day
----------------------------------------------------------------------------
DECLARE @CalisthenicsSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'Calisthenics Foundations');

INSERT INTO dbo.SplitDayExercises (SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
SELECT sd.SplitDayId, e.ExerciseId, v.SortOrder, v.TargetSets, v.TargetRepsLow, v.TargetRepsHigh
FROM (VALUES
    (1, N'Push-Up', 1, 4, 10, 15),
    (1, N'Bodyweight Dip', 2, 3, 8, 10),
    (1, N'Plank Hold', 3, 3, 30, 45),
    (2, N'Pull-Up', 1, 4, 6, 10),
    (2, N'Inverted Row (Bodyweight)', 2, 3, 10, 12),
    (2, N'Hanging Leg Raise', 3, 3, 10, 12),
    (3, N'Bodyweight Squat', 1, 4, 15, 20),
    (3, N'Inverted Row (Bodyweight)', 2, 3, 10, 12),
    (3, N'Plank Hold', 3, 3, 45, 45)
) AS v(DayIndex, ExerciseName, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
INNER JOIN dbo.SplitDays sd ON sd.SplitId = @CalisthenicsSplitId AND sd.DayIndex = v.DayIndex
INNER JOIN dbo.Exercises e ON e.Name = v.ExerciseName
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.SplitDayExercises sde
    WHERE sde.SplitDayId = sd.SplitDayId AND sde.ExerciseId = e.ExerciseId
);
GO

----------------------------------------------------------------------------
-- Split days for 2-Day Maintenance Full Body
----------------------------------------------------------------------------
DECLARE @MaintenanceSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'2-Day Maintenance Full Body');

INSERT INTO dbo.SplitDays (SplitId, DayIndex, Title, FocusLabel, EstimatedMinutes)
SELECT @MaintenanceSplitId, v.DayIndex, v.Title, v.FocusLabel, v.EstimatedMinutes
FROM (VALUES
    (1, N'Full Body A', N'General Strength', 40),
    (2, N'Full Body B', N'General Strength', 40)
) AS v(DayIndex, Title, FocusLabel, EstimatedMinutes)
WHERE @MaintenanceSplitId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.SplitDays d WHERE d.SplitId = @MaintenanceSplitId AND d.DayIndex = v.DayIndex);
GO

----------------------------------------------------------------------------
-- Target exercises per 2-Day Maintenance Full Body split day
----------------------------------------------------------------------------
DECLARE @MaintenanceSplitId UNIQUEIDENTIFIER = (SELECT SplitId FROM dbo.WorkoutSplits WHERE Name = N'2-Day Maintenance Full Body');

INSERT INTO dbo.SplitDayExercises (SplitDayId, ExerciseId, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
SELECT sd.SplitDayId, e.ExerciseId, v.SortOrder, v.TargetSets, v.TargetRepsLow, v.TargetRepsHigh
FROM (VALUES
    (1, N'Barbell High-Bar Back Squat', 1, 3, 8, 10),
    (1, N'Push-Up', 2, 3, 12, 15),
    (1, N'Seated Cable Row', 3, 3, 10, 12),
    (1, N'Plank Hold', 4, 3, 30, 45),
    (2, N'Romanian Deadlift (Dumbbells)', 1, 3, 10, 12),
    (2, N'Seated Dumbbell Overhead Press', 2, 3, 10, 12),
    (2, N'Wide-Grip Lat Pulldown', 3, 3, 10, 12),
    (2, N'Cable Crunch', 4, 3, 15, 20)
) AS v(DayIndex, ExerciseName, SortOrder, TargetSets, TargetRepsLow, TargetRepsHigh)
INNER JOIN dbo.SplitDays sd ON sd.SplitId = @MaintenanceSplitId AND sd.DayIndex = v.DayIndex
INNER JOIN dbo.Exercises e ON e.Name = v.ExerciseName
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.SplitDayExercises sde
    WHERE sde.SplitDayId = sd.SplitDayId AND sde.ExerciseId = e.ExerciseId
);
GO

----------------------------------------------------------------------------
-- Subscription plans
----------------------------------------------------------------------------
-- Prices are EUR. PRO leads the paid tier at 2.49/mo (the cheapest upgrade),
-- ADVANCED at 4.99/mo; yearly is ~30% off the monthly*12 sticker price - see
-- the "-30%" yearly toggle badge in plans_screen.dart, which must stay in
-- sync with these two ratios.
INSERT INTO dbo.SubscriptionPlans (Code, Name, Tagline, MonthlyPrice, YearlyPrice, IsFeatured, SortOrder)
SELECT v.Code, v.Name, v.Tagline, v.MonthlyPrice, v.YearlyPrice, v.IsFeatured, v.SortOrder
FROM (VALUES
    (N'FREE', N'Free Tier', N'Essential hardware tracking and routine logging for self-guided lifters.', 0.00, 0.00, 0, 1),
    (N'PRO', N'Pro Tier', N'Advanced volume telemetry, predictive PR curves, and automated deload signals.', 2.49, 20.99, 1, 2),
    (N'ADVANCED', N'Advanced Tier', N'Weekly AI check-ins, on-demand AI-generated plans, and unlimited splits & diet plans.', 4.99, 41.99, 0, 3)
) AS v(Code, Name, Tagline, MonthlyPrice, YearlyPrice, IsFeatured, SortOrder)
WHERE NOT EXISTS (SELECT 1 FROM dbo.SubscriptionPlans p WHERE p.Code = v.Code);
GO

-- Re-runnable price correction for a database already seeded from an earlier
-- version of this file (the INSERT above is a no-op once a Code row exists).
UPDATE p
SET p.MonthlyPrice = v.MonthlyPrice, p.YearlyPrice = v.YearlyPrice
FROM dbo.SubscriptionPlans p
INNER JOIN (VALUES
    (N'FREE', 0.00, 0.00),
    (N'PRO', 2.49, 20.99),
    (N'ADVANCED', 4.99, 41.99)
) AS v(Code, MonthlyPrice, YearlyPrice) ON v.Code = p.Code;
GO

-- Re-runnable tagline correction, same reasoning as the price correction above.
UPDATE p
SET p.Tagline = v.Tagline
FROM dbo.SubscriptionPlans p
INNER JOIN (VALUES
    (N'ADVANCED', N'Weekly AI check-ins, on-demand AI-generated plans, and unlimited splits & diet plans.')
) AS v(Code, Tagline) ON v.Code = p.Code AND p.Tagline <> v.Tagline;
GO

INSERT INTO dbo.PlanFeatures (PlanId, FeatureText, SortOrder, IsHighlighted)
SELECT p.PlanId, v.FeatureText, v.SortOrder, v.IsHighlighted
FROM (VALUES
    (N'FREE', N'Routine logging & workout telemetry', 1, 0),
    (N'FREE', N'Standard split templates (PPL, Upper/Lower)', 2, 0),
    (N'FREE', N'Basic streak & calendar volume view', 3, 0),
    (N'FREE', N'Push notifications for daily gym attendance', 4, 0),
    (N'PRO', N'Everything included in Free tier', 1, 0),
    (N'PRO', N'AI Monthly Overview & Volume Synthesis', 2, 1),
    (N'PRO', N'Advanced 1RM progression & PR prediction', 3, 0),
    (N'PRO', N'Intelligent recovery & deload detection', 4, 0),
    (N'PRO', N'Custom split builder with infinite routines', 5, 0),
    (N'ADVANCED', N'Everything included in Pro tier', 1, 0),
    (N'ADVANCED', N'Adaptive meal planner calibrated to load', 2, 1),
    (N'ADVANCED', N'Weekly AI check-ins with prioritized recommendations', 3, 0),
    (N'ADVANCED', N'AI-generated workout splits & diet plans on request', 4, 0),
    (N'ADVANCED', N'Unlimited saved splits & diet plans', 5, 0)
) AS v(Code, FeatureText, SortOrder, IsHighlighted)
INNER JOIN dbo.SubscriptionPlans p ON p.Code = v.Code
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.PlanFeatures pf WHERE pf.PlanId = p.PlanId AND pf.FeatureText = v.FeatureText
);
GO

-- Re-runnable correction: earlier seeds advertised Advanced features that were
-- never implemented (live grocery lists, real-time AI form feedback, a 1-on-1
-- coach chat). Rewrite those existing rows to what Advanced actually ships -
-- the weekly AI check-in, on-demand AI generation, and unlimited saved
-- splits/diet plans built in this deploy - instead of inserting duplicates.
UPDATE pf
SET pf.FeatureText = v.NewText
FROM dbo.PlanFeatures pf
INNER JOIN dbo.SubscriptionPlans p ON p.PlanId = pf.PlanId
INNER JOIN (VALUES
    (N'ADVANCED', N'Live grocery list & instant recipe matching', N'Weekly AI check-ins with prioritized recommendations'),
    (N'ADVANCED', N'Real-time AI form feedback & auto-adjustments', N'AI-generated workout splits & diet plans on request'),
    (N'ADVANCED', N'1-on-1 AI coach chat assistant', N'Unlimited saved splits & diet plans')
) AS v(Code, OldText, NewText) ON v.Code = p.Code AND pf.FeatureText = v.OldText;
GO

----------------------------------------------------------------------------
-- AI prompt template: monthly analytics report (Pro/Advanced only)
----------------------------------------------------------------------------
-- Prompt text lives as data (dbo.AiPromptTemplates) rather than a C# string
-- literal so it can be tuned without a deploy - AnalyticsService substitutes
-- every {{Placeholder}} token below with a given user's real numbers from
-- usp_Analytics_GetMonthlySnapshot before calling OpenRouter.
INSERT INTO dbo.AiPromptTemplates (TemplateKey, SystemPrompt, UserPromptTemplate, Model, IsActive)
SELECT
    N'MonthlyAnalytics',
    N'You are Silen''s in-house strength & conditioning coach. You write concise, encouraging, ' +
    N'data-grounded monthly progress reports for a fitness-tracking app''s paying subscribers. ' +
    N'Only comment on the numbers you are given - never invent data points. Keep language direct ' +
    N'and specific, avoid generic filler, and always respond with strict JSON matching the ' +
    N'requested schema and nothing else.',
    N'Write this month''s progress report for {{DisplayName}} covering {{PeriodLabel}}.' + CHAR(10) + CHAR(10) +
    N'Training:' + CHAR(10) +
    N'- Completed sessions: {{CompletedSessions}} of {{ScheduledSessions}} scheduled' + CHAR(10) +
    N'- Total tonnage lifted: {{TotalTonnageKg}} kg' + CHAR(10) +
    N'- Average session RPE: {{AvgRpe}}' + CHAR(10) +
    N'- Current daily streak: {{CurrentStreakDays}} days' + CHAR(10) +
    N'- This week''s compliance: {{WeeklyCompliancePercent}}%' + CHAR(10) + CHAR(10) +
    N'Bodyweight trend: {{WeightTrendSummary}}' + CHAR(10) +
    N'Nutrition adherence: {{NutritionAdherenceSummary}}' + CHAR(10) + CHAR(10) +
    N'Return strict JSON with this exact shape: {"strengths": string[], ' +
    N'"improvements": [{"area": string, "recommendation": string, "priority": "Low"|"Medium"|"High"}], ' +
    N'"focusForNextMonth": string}. List 2-4 strengths and 2-4 improvements grounded only in the ' +
    N'data above.',
    N'openai/gpt-4.1',
    1
WHERE NOT EXISTS (SELECT 1 FROM dbo.AiPromptTemplates t WHERE t.TemplateKey = N'MonthlyAnalytics');
GO

---------------------------------------------------------------------------
-- AI prompt template: weekly analytics report (Advanced only)
---------------------------------------------------------------------------
-- The weekly counterpart of MonthlyAnalytics above - same placeholder contract
-- (see AnalyticsService.BuildUserPrompt), but scoped to a 7-day ISO week and
-- asked to write a "focusForNextWeek" instead of a "focusForNextMonth".
INSERT INTO dbo.AiPromptTemplates (TemplateKey, SystemPrompt, UserPromptTemplate, Model, IsActive)
SELECT
    N'WeeklyAnalytics',
    N'You are Silen''s in-house strength & conditioning coach. You write concise, encouraging, ' +
    N'data-grounded weekly progress check-ins for a fitness-tracking app''s top-tier subscribers. ' +
    N'Only comment on the numbers you are given - never invent data points. Keep language direct ' +
    N'and specific, avoid generic filler, and always respond with strict JSON matching the ' +
    N'requested schema and nothing else.',
    N'Write this week''s progress check-in for {{DisplayName}} covering {{PeriodLabel}}.' + CHAR(10) + CHAR(10) +
    N'Training:' + CHAR(10) +
    N'- Completed sessions: {{CompletedSessions}} of {{ScheduledSessions}} scheduled' + CHAR(10) +
    N'- Total tonnage lifted: {{TotalTonnageKg}} kg' + CHAR(10) +
    N'- Average session RPE: {{AvgRpe}}' + CHAR(10) +
    N'- Current daily streak: {{CurrentStreakDays}} days' + CHAR(10) +
    N'- This week''s compliance: {{WeeklyCompliancePercent}}%' + CHAR(10) + CHAR(10) +
    N'Bodyweight trend: {{WeightTrendSummary}}' + CHAR(10) +
    N'Nutrition adherence: {{NutritionAdherenceSummary}}' + CHAR(10) + CHAR(10) +
    N'This is a weekly check-in, so keep it short and actionable - a handful of wins, the one or ' +
    N'two things worth adjusting next week, and one concrete habit. Return strict JSON with this ' +
    N'exact shape: {"strengths": string[], ' +
    N'"improvements": [{"area": string, "recommendation": string, "priority": "Low"|"Medium"|"High"}], ' +
    N'"focusForNextWeek": string}. List 1-3 strengths and 1-3 improvements grounded only in the ' +
    N'data above.',
    N'openai/gpt-4.1',
    1
WHERE NOT EXISTS (SELECT 1 FROM dbo.AiPromptTemplates t WHERE t.TemplateKey = N'WeeklyAnalytics');
GO

---------------------------------------------------------------------------
-- Advanced plan feature: weekly AI overview (top tier only)
---------------------------------------------------------------------------
INSERT INTO dbo.PlanFeatures (PlanId, FeatureText, SortOrder, IsHighlighted)
SELECT p.PlanId, N'Weekly AI Overview with meal & split suggestions', 6, 1
FROM dbo.SubscriptionPlans p
WHERE p.Code = N'ADVANCED'
  AND NOT EXISTS (
      SELECT 1 FROM dbo.PlanFeatures pf
      WHERE pf.PlanId = p.PlanId AND pf.FeatureText = N'Weekly AI Overview with meal & split suggestions'
  );
GO
