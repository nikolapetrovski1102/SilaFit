USE SilenDb;
GO

-- Backfills Exercises.DemoVideoUrl with form-reference photos from
-- free-exercise-db (https://github.com/yuhonas/free-exercise-db),
-- explicitly public-domain per that repo's README - safe to ship without
-- attribution. NOTE: that source has step-position JPEGs, not actual
-- video, so this seeds photo URLs into a column named for video; the
-- Active Workout Tracker's demo sheet (active_workout_tracker_screen.dart)
-- already detects the file extension and renders a static photo instead
-- of a video player for these. Swap in real .mp4 URLs here later without
-- any other change needed.
--
-- A few rows are the closest available match rather than an exact one -
-- see the inline comment on each; free-exercise-db doesn't have every
-- exact variant (e.g. no Bulgarian-specific split squat, no dumbbell RDL).
-- Idempotent: always overwrites to the current mapping, safe to re-run.

UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Incline_Dumbbell_Press/1.jpg' WHERE Name = N'Incline Dumbbell Bench Press';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Seated_Dumbbell_Press/1.jpg' WHERE Name = N'Seated Dumbbell Overhead Press';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Cable_Crossover/1.jpg' WHERE Name = N'Cable Standing Flyes'; -- closest cable-fly equivalent; source has no exact 'standing flyes' entry
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Barbell_Deadlift/1.jpg' WHERE Name = N'Barbell Conventional Deadlift';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Wide-Grip_Lat_Pulldown/1.jpg' WHERE Name = N'Wide-Grip Lat Pulldown';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Incline_Hammer_Curls/1.jpg' WHERE Name = N'Incline Dumbbell Hammer Curl';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Barbell_Squat/1.jpg' WHERE Name = N'Barbell High-Bar Back Squat'; -- source's generic barbell squat; no high-bar-specific entry
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Romanian_Deadlift/1.jpg' WHERE Name = N'Romanian Deadlift (Dumbbells)'; -- source shows barbell RDL; no dumbbell variant in db
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Leg_Extensions/1.jpg' WHERE Name = N'Seated Leg Extension';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Barbell_Incline_Bench_Press_-_Medium_Grip/1.jpg' WHERE Name = N'Incline Barbell Bench Press';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Lying_T-Bar_Row/1.jpg' WHERE Name = N'Chest-Supported T-Bar Row'; -- closest chest-supported T-bar row equivalent
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Split_Squats/1.jpg' WHERE Name = N'Bulgarian Split Squat'; -- generic split squat; source has no rear-foot-elevated variant
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Cable_Seated_Lateral_Raise/1.jpg' WHERE Name = N'Cable Lateral Raise'; -- closest cable lateral raise; source variant is seated
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Cable_Rope_Overhead_Triceps_Extension/1.jpg' WHERE Name = N'Overhead Rope Extension';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Barbell_Hip_Thrust/1.jpg' WHERE Name = N'Barbell Hip Thrust';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Pull_Through/1.jpg' WHERE Name = N'Cable Pull-Through';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Bodyweight_Walking_Lunge/1.jpg' WHERE Name = N'Walking Lunge (Dumbbells)'; -- source has no dumbbell variant; bodyweight form is closest
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Standing_Calf_Raises/1.jpg' WHERE Name = N'Standing Calf Raise (Machine)';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Face_Pull/1.jpg' WHERE Name = N'Face Pull';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Front_Barbell_Squat/1.jpg' WHERE Name = N'Barbell Front Squat';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Pushups/1.jpg' WHERE Name = N'Push-Up';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Weighted_Pull_Ups/1.jpg' WHERE Name = N'Pull-Up'; -- source has no plain bodyweight pull-up; weighted variant is the closest movement match
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Dips_-_Triceps_Version/1.jpg' WHERE Name = N'Bodyweight Dip';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Bodyweight_Squat/1.jpg' WHERE Name = N'Bodyweight Squat';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Plank/1.jpg' WHERE Name = N'Plank Hold';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Hanging_Leg_Raise/1.jpg' WHERE Name = N'Hanging Leg Raise';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Close-Grip_Barbell_Bench_Press/1.jpg' WHERE Name = N'Close-Grip Bench Press';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Bent_Over_Barbell_Row/1.jpg' WHERE Name = N'Barbell Bent-Over Row';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Seated_Cable_Rows/1.jpg' WHERE Name = N'Seated Cable Row';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Goblet_Squat/1.jpg' WHERE Name = N'Dumbbell Goblet Squat';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/One-Arm_Kettlebell_Swings/1.jpg' WHERE Name = N'Kettlebell Swing'; -- source has no two-arm swing entry
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Cable_Crunch/1.jpg' WHERE Name = N'Cable Crunch';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Barbell_Shrug/1.jpg' WHERE Name = N'Barbell Shrug';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Inverted_Row/1.jpg' WHERE Name = N'Inverted Row (Bodyweight)';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Side_Lateral_Raise/1.jpg' WHERE Name = N'Dumbbell Lateral Raise';
UPDATE dbo.Exercises SET DemoVideoUrl = N'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Barbell_Curl/1.jpg' WHERE Name = N'Barbell Curl';
GO
