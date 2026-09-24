USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- One-time cleanup of the exercise catalogue behind the split-builder search,
-- which listed the same exercise under several spellings ("Push Up", "Push Ups",
-- "Push-Ups", "Pushups") and put many M&S imports under the wrong muscle group
-- (the old importer defaulted anything it didn't recognise to core).
--
-- 1. Merges: each hand-reviewed (variant, canonical) pair in
--    tools/muscleandstrength_scraper/exercise_aliases.csv. Split-day rows and
--    logged sets move to the canonical row; the variant is deleted only when
--    nothing references it any more. A split day that already lists the
--    canonical exercise keeps its variant row untouched (so no day ends up
--    with the same exercise twice), and that variant then survives.
-- 2. Muscle groups: a reviewed rename applies only while the row still has the
--    group it had when reviewed, so admin edits made since are never overwritten.
--    Admin-edited rows and hand-written reference exercises were left out of
--    the list on purpose.
--
-- Idempotent: re-running changes nothing once applied, and it cleans up again
-- if an old seed ever re-creates a merged spelling. The importer now maps these
-- spellings itself (generate_sql.py), so the regenerated 006 seed won't.
--
-- Rows touched are copied to dbo._bak_* tables first (kept until dropped by hand).

SET XACT_ABORT ON;
SET NOCOUNT ON;

DECLARE @Merges TABLE (Variant NVARCHAR(150) NOT NULL, Canonical NVARCHAR(150) NOT NULL);
INSERT INTO @Merges (Variant, Canonical) VALUES
    (N'1 Leg Pushups', N'1 Leg Push Up'),
    (N'Ab Crunches', N'Ab Crunch'),
    (N'Air Squats', N'Air Squat'),
    (N'Band Pull Apart', N'Band Pull-Apart'),
    (N'Banded Glute Bridges', N'Banded Glute Bridge'),
    (N'Banded Good Morning *', N'Banded Good Morning'),
    (N'Flat Barbell Bench Press', N'Barbell Bench Press'),
    (N'Barbell Curls', N'Barbell Curl'),
    (N'4. Barbell Hip Thrust', N'Barbell Hip Thrust'),
    (N'Barbell Hip Thrusts', N'Barbell Hip Thrust'),
    (N'Barbell Romanian Deadlift', N'Barbell Romanian Deadlifts'),
    (N'Barbell Row', N'Barbell Rows'),
    (N'Barbell Shrugs', N'Barbell Shrug'),
    (N'Flat Bench Press', N'Bench Press'),
    (N'Bent-Over Dumbbell Row', N'Bent Over Dumbbell Row'),
    (N'Bicep Curls', N'Bicep Curl'),
    (N'Bicycle Crunches', N'Bicycle Crunch'),
    (N'Bodyweight Single Leg Deadlift', N'Bodyweight Single-Leg Deadlift'),
    (N'Bodyweight Squats', N'Bodyweight Squat'),
    (N'Box Squats', N'Box Squat'),
    (N'Bulgarian Split Squats', N'Bulgarian Split Squat'),
    (N'Cable Face Pulls', N'Cable Face Pull'),
    (N'Cable Pull Through', N'Cable Pull-Through'),
    (N'Cable Tricep Extensions', N'Cable Tricep Extension'),
    (N'Chest Dip **', N'Chest Dip'),
    (N'Chin Ups', N'Chin Up'),
    (N'Close Grip Lat Pulldown', N'Close Grip Lat Pull Down'),
    (N'Close Grip Push Ups', N'Close Grip Push Up'),
    (N'Close-Grip Push-Up', N'Close Grip Push Up'),
    (N'Close Grip Bench Press', N'Close-Grip Bench Press'),
    (N'3. Crunches', N'Crunches'),
    (N'Crunch', N'Crunches'),
    (N'Deadlifts', N'Deadlift'),
    (N'Decline Sit Ups', N'Decline Sit Up'),
    (N'Dips *', N'Dips'),
    (N'Flat Dumbbell Bench Press', N'Dumbbell Bench Press'),
    (N'Dumbbell Curls', N'Dumbbell Curl'),
    (N'Dumbbell Fly', N'Dumbbell Flys'),
    (N'Flat Dumbbell Fly', N'Dumbbell Flys'),
    (N'Dumbbell Lunges', N'Dumbbell Lunge'),
    (N'Dumbbell Reverse Flye', N'Dumbbell Reverse Fly'),
    (N'Dumbbell Shrugs', N'Dumbbell Shrug'),
    (N'3. Dumbbell Step Up', N'Dumbbell Step Up'),
    (N'Dumbbell Step Ups', N'Dumbbell Step Up'),
    (N'3. Dumbbell Stiff Leg Deadlift', N'Dumbbell Stiff Leg Deadlift'),
    (N'Dumbbell Tricep Kickback', N'Dumbbell Tricep Kickbacks'),
    (N'Exercise Ball Crunches', N'Exercise Ball Crunch'),
    (N'EZ Bar Curls', N'EZ Bar Curl'),
    (N'Face Pulls', N'Face Pull'),
    (N'Glute Bridges', N'Glute Bridge'),
    (N'Glute Cable Kickbacks', N'Glute Cable Kickback'),
    (N'Glute Kickbacks', N'Glute Kick Back'),
    (N'Goblet Squats', N'Goblet Squat'),
    (N'Good Mornings', N'Good Morning'),
    (N'Hanging Knee Raises', N'Hanging Knee Raise'),
    (N'Hanging Leg Raises', N'Hanging Leg Raise'),
    (N'4. Incline Dumbbell Curl', N'Incline Dumbbell Curl'),
    (N'Incline Dumbbell Fly', N'Incline Dumbbell Flys'),
    (N'Inverted Rows', N'Inverted Row'),
    (N'Jump Squats', N'Jump Squat'),
    (N'Jumping Lunge', N'Jumping Lunges'),
    (N'Kettlebell Swings', N'Kettlebell Swing'),
    (N'Lateral Raises', N'Lateral Raise'),
    (N'Leg Curls', N'Leg Curl'),
    (N'3. Leg Extensions', N'Leg Extension'),
    (N'Leg Extensions', N'Leg Extension'),
    (N'Lying Leg Curl *', N'Lying Leg Curl'),
    (N'Lying Leg Curls', N'Lying Leg Curl'),
    (N'Lying Leg Raises', N'Lying Leg Raise'),
    (N'Lying Tricep Extension', N'Lying Triceps Extension'),
    (N'Lying Tricep Extensions', N'Lying Triceps Extension'),
    (N'3. Machine Chest Fly', N'Machine Chest Fly'),
    (N'Neutral Grip Pull Up *', N'Neutral Grip Pull Up'),
    (N'Oblique Crunches', N'Oblique Crunch'),
    (N'One Arm Dumbbell Rows', N'One Arm Dumbbell Row'),
    (N'Overhead Tricep Extension', N'Overhead Triceps Extension'),
    (N'Plie Squats', N'Plie Squat'),
    (N'Pull Up', N'Pull-Up'),
    (N'Pull Ups', N'Pull-Up'),
    (N'Pull Ups *', N'Pull-Up'),
    (N'Push Up', N'Push-Up'),
    (N'Push Up **', N'Push-Up'),
    (N'Push Ups', N'Push-Up'),
    (N'Push-Ups', N'Push-Up'),
    (N'Pushups', N'Push-Up'),
    (N'Reverse Hack Squat', N'Reverse Hack Squats'),
    (N'Reverse Lunges', N'Reverse Lunge'),
    (N'2. Romanian Deadlift', N'Romanian Deadlift'),
    (N'Rope Press Down', N'Rope Pressdown'),
    (N'Russian Twists', N'Russian Twist'),
    (N'3. Seated Cable Row', N'Seated Cable Row'),
    (N'Seated Calf Raise **', N'Seated calf Raise'),
    (N'4. Seated Dumbbell Press', N'Seated Dumbbell Press'),
    (N'Seated Leg Extensions', N'Seated Leg Extension'),
    (N'4. Side Crunches', N'Side Crunch'),
    (N'Side Crunches', N'Side Crunch'),
    (N'Single Leg Calf Raise', N'Single-Leg Calf Raise'),
    (N'Sit-Up', N'Sit Up'),
    (N'Skullcrushers', N'Skullcrusher'),
    (N'4. Smith Machine Sumo Squats (Glute Focus)', N'Smith Machine Sumo Squats (Glute Focus)'),
    (N'Spider Curls', N'Spider Curl'),
    (N'Squats', N'Squat'),
    (N'Standing Barbell Curl', N'Standing Barbell Curls'),
    (N'Standing Calf Raises', N'Standing Calf Raise'),
    (N'Stiff-Leg Deadlift', N'Stiff Leg Deadlift'),
    (N'Stiff Legged Deadlift', N'Stiff-Legged Deadlift'),
    (N'Sumo Deadlifts', N'Sumo Deadlift'),
    (N'Sumo Squats', N'Sumo Squat'),
    (N'T Bar Row', N'T-Bar Row'),
    (N'Tricep Extensions', N'Tricep Extension'),
    (N'Triceps Push Down', N'Tricep Pushdown'),
    (N'Walking Lunges', N'Walking Lunge'),
    (N'Wide Grip Lat Pull Down', N'Wide-Grip Lat Pulldown'),
    (N'Wide Grip Lat Pulldown', N'Wide-Grip Lat Pulldown');

DECLARE @GroupFixes TABLE (Name NVARCHAR(150) NOT NULL, FromGroup NVARCHAR(30) NOT NULL, ToGroup NVARCHAR(30) NOT NULL);
INSERT INTO @GroupFixes (Name, FromGroup, ToGroup) VALUES
    (N'1 Leg Push Up', N'legs', N'chest'),
    (N'Abduction Machine (or Banded)', N'core', N'legs'),
    (N'Abductor Machine', N'core', N'legs'),
    (N'Adduction Machine', N'core', N'legs'),
    (N'Adduction Machine (or Banded)', N'core', N'legs'),
    (N'Adductor Machine', N'core', N'legs'),
    (N'Alternating Standing Arnold Press', N'core', N'shoulders'),
    (N'Alternating Swing', N'core', N'legs'),
    (N'Arm Circles', N'core', N'shoulders'),
    (N'Arm Circles (Clockwise)', N'core', N'shoulders'),
    (N'Arm Circles (Counter Clockwise)', N'core', N'shoulders'),
    (N'Arnold Press', N'core', N'shoulders'),
    (N'Band Pull-Apart', N'core', N'shoulders'),
    (N'Barbell Good Mornings', N'core', N'legs'),
    (N'Barbell Upright Row', N'back', N'shoulders'),
    (N'Bent Over Reverse Fly', N'chest', N'shoulders'),
    (N'Bodyweight Hyperextensions', N'core', N'legs'),
    (N'Box Jump', N'core', N'legs'),
    (N'Box Jumps', N'core', N'legs'),
    (N'Cable Crossover', N'core', N'chest'),
    (N'Cable Pullthrough', N'core', N'legs'),
    (N'Chest Supported Dumbbell Row', N'chest', N'back'),
    (N'Chest Supported Rows', N'chest', N'back'),
    (N'Closegrip Bench Press - Power', N'chest', N'arms'),
    (N'DB Bench', N'core', N'chest'),
    (N'Donkey Kicks', N'core', N'legs'),
    (N'Dumbbell Arnold Press', N'core', N'shoulders'),
    (N'Dumbbell Floor Press', N'core', N'chest'),
    (N'Dumbbell Kickback', N'core', N'arms'),
    (N'Dumbbell Overhead Extension', N'core', N'arms'),
    (N'Dumbbell Pull Over', N'core', N'chest'),
    (N'Dumbbell Upright Row', N'back', N'shoulders'),
    (N'EZ Bar Overhead Extension', N'core', N'arms'),
    (N'Fire Hydrant', N'core', N'legs'),
    (N'Flat Bench Dumbbell Press', N'back', N'chest'),
    (N'Frog Pump', N'core', N'legs'),
    (N'Frog Pumps', N'core', N'legs'),
    (N'Glute Bridge Pallof Press', N'legs', N'core'),
    (N'Half Kneeling Facepull', N'core', N'shoulders'),
    (N'Half Kneeling Press', N'core', N'shoulders'),
    (N'Hyperextension', N'core', N'legs'),
    (N'Hyperextensions', N'core', N'legs'),
    (N'KB Swing', N'core', N'legs'),
    (N'Kettlebell Press', N'core', N'shoulders'),
    (N'Landmine RDL', N'core', N'legs'),
    (N'Leg Lifts', N'legs', N'core'),
    (N'Lying Abduction (dumbbells/bands*)', N'core', N'legs'),
    (N'Lying Adduction (dumbbells/bands*)', N'core', N'legs'),
    (N'Lying Dumbbell Extension', N'core', N'arms'),
    (N'Lying Leg Lift', N'legs', N'core'),
    (N'Neutral Grip Dumbbell Press', N'core', N'chest'),
    (N'Obliques Curl', N'arms', N'core'),
    (N'One Arm Dumbbell Press', N'core', N'chest'),
    (N'One Arm Landmine Push Press', N'core', N'shoulders'),
    (N'One Arm Overhead Dumbbell Extension', N'core', N'arms'),
    (N'Overhead Dumbbell Extension', N'core', N'arms'),
    (N'Overhead Press', N'core', N'shoulders'),
    (N'Pec Deck', N'core', N'chest'),
    (N'Resistance Band Overhead Press', N'core', N'shoulders'),
    (N'Reverse Hyperextension', N'core', N'legs'),
    (N'Reverse Pec-Deck', N'core', N'shoulders'),
    (N'Seated Arnold Press - Muscle', N'core', N'shoulders'),
    (N'Seated Barbell Press', N'core', N'shoulders'),
    (N'Seated Barbell Press - Power', N'core', N'shoulders'),
    (N'Seated Behind the Neck Press', N'core', N'shoulders'),
    (N'Seated Dumbbell Press', N'core', N'shoulders'),
    (N'Seated French Press - Muscle', N'core', N'arms'),
    (N'Seated Machine Reverse Fly', N'chest', N'shoulders'),
    (N'Seated One Arm Dumbbell Extrension', N'core', N'arms'),
    (N'Seated Smith Machine Press', N'core', N'shoulders'),
    (N'Side Clams', N'core', N'legs'),
    (N'Side Lying Clams', N'core', N'legs'),
    (N'Single Arm Overhead Extension', N'core', N'arms'),
    (N'Skull Crushers', N'core', N'arms'),
    (N'Smith Machine Close Grip Bench Press', N'chest', N'arms'),
    (N'Smith Machine Upright Row', N'back', N'shoulders'),
    (N'Standing Cable Crossovers', N'core', N'chest'),
    (N'Standing Cable Reverse Fly', N'chest', N'shoulders'),
    (N'Standing Dumbbell Press', N'core', N'shoulders'),
    (N'Standing Overhead Press', N'core', N'shoulders'),
    (N'Standing Overhead Press (Use 20% less weight than your previous working sets)', N'core', N'shoulders'),
    (N'Straight Leg Toe Touch', N'legs', N'core'),
    (N'Strict Overhead Press', N'core', N'shoulders'),
    (N'Superman', N'core', N'back'),
    (N'Two Arm Seated Dumbbell Extension', N'core', N'arms'),
    (N'Upright Row', N'back', N'shoulders'),
    (N'Vertical Jumps', N'core', N'legs'),
    (N'Weighted Hyperextension', N'core', N'legs'),
    (N'Z Press', N'core', N'shoulders');

-- Resolve to ids. Both names must exist exactly once; anything ambiguous is skipped.
DECLARE @Pairs TABLE (VariantId UNIQUEIDENTIFIER NOT NULL PRIMARY KEY, CanonicalId UNIQUEIDENTIFIER NOT NULL);
INSERT INTO @Pairs (VariantId, CanonicalId)
SELECT v.ExerciseId, c.ExerciseId
FROM @Merges m
JOIN dbo.Exercises v ON v.Name = m.Variant
JOIN dbo.Exercises c ON c.Name = m.Canonical
WHERE v.ExerciseId <> c.ExerciseId
  AND (SELECT COUNT(*) FROM dbo.Exercises x WHERE x.Name = m.Variant) = 1
  AND (SELECT COUNT(*) FROM dbo.Exercises x WHERE x.Name = m.Canonical) = 1;

PRINT CONCAT('Merge pairs present: ', @@ROWCOUNT);

BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo._bak_Exercises_028') IS NULL
    SELECT * INTO dbo._bak_Exercises_028 FROM dbo.Exercises WHERE 1 = 0;
IF OBJECT_ID(N'dbo._bak_SplitDayExercises_028') IS NULL
    SELECT SplitDayExerciseId, ExerciseId, SYSUTCDATETIME() AS BackedUpAtUtc INTO dbo._bak_SplitDayExercises_028 FROM dbo.SplitDayExercises WHERE 1 = 0;
IF OBJECT_ID(N'dbo._bak_WorkoutSetLogs_028') IS NULL
    SELECT WorkoutSetLogId, ExerciseId, SYSUTCDATETIME() AS BackedUpAtUtc INTO dbo._bak_WorkoutSetLogs_028 FROM dbo.WorkoutSetLogs WHERE 1 = 0;

INSERT INTO dbo._bak_Exercises_028
SELECT e.* FROM dbo.Exercises e
WHERE e.ExerciseId IN (SELECT VariantId FROM @Pairs)
   OR EXISTS (SELECT 1 FROM @GroupFixes g WHERE g.Name = e.Name AND g.FromGroup = e.MuscleGroup);

INSERT INTO dbo._bak_SplitDayExercises_028 (SplitDayExerciseId, ExerciseId, BackedUpAtUtc)
SELECT SplitDayExerciseId, ExerciseId, SYSUTCDATETIME() FROM dbo.SplitDayExercises
WHERE ExerciseId IN (SELECT VariantId FROM @Pairs);

INSERT INTO dbo._bak_WorkoutSetLogs_028 (WorkoutSetLogId, ExerciseId, BackedUpAtUtc)
SELECT WorkoutSetLogId, ExerciseId, SYSUTCDATETIME() FROM dbo.WorkoutSetLogs
WHERE ExerciseId IN (SELECT VariantId FROM @Pairs);

UPDATE sde SET ExerciseId = p.CanonicalId
FROM dbo.SplitDayExercises sde
JOIN @Pairs p ON p.VariantId = sde.ExerciseId
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.SplitDayExercises other
    WHERE other.SplitDayId = sde.SplitDayId AND other.ExerciseId = p.CanonicalId);
PRINT CONCAT('Split-day rows repointed: ', @@ROWCOUNT);

UPDATE l SET ExerciseId = p.CanonicalId
FROM dbo.WorkoutSetLogs l
JOIN @Pairs p ON p.VariantId = l.ExerciseId
-- Keep sets on the variant while a split day still uses it, so the session
-- screen (keyed by ExerciseId) still finds its history.
WHERE NOT EXISTS (SELECT 1 FROM dbo.SplitDayExercises sde WHERE sde.ExerciseId = p.VariantId);
PRINT CONCAT('Logged sets repointed: ', @@ROWCOUNT);

DELETE e FROM dbo.Exercises e
JOIN @Pairs p ON p.VariantId = e.ExerciseId
WHERE NOT EXISTS (SELECT 1 FROM dbo.SplitDayExercises sde WHERE sde.ExerciseId = e.ExerciseId)
  AND NOT EXISTS (SELECT 1 FROM dbo.WorkoutSetLogs l WHERE l.ExerciseId = e.ExerciseId);
PRINT CONCAT('Duplicate exercises deleted: ', @@ROWCOUNT);

UPDATE e SET MuscleGroup = g.ToGroup
FROM dbo.Exercises e
JOIN @GroupFixes g ON g.Name = e.Name AND g.FromGroup = e.MuscleGroup;
PRINT CONCAT('Muscle groups corrected: ', @@ROWCOUNT);

COMMIT TRANSACTION;

SELECT m.Variant, m.Canonical, 'kept - still referenced' AS Status
FROM @Merges m JOIN dbo.Exercises v ON v.Name = m.Variant
WHERE EXISTS (SELECT 1 FROM dbo.Exercises c WHERE c.Name = m.Canonical);
GO
