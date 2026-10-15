-- Catalog split clean-up: rest days, broken imported days, placeholder reps.
--
-- A split's rotation is Monday-anchored and whole weeks long: DayIndex N is
-- weekday N (1 = Mon ... 7 = Sun) and any index with no SplitDay is a rest day.
-- The imported catalog numbered every split's days 1..N, so they all trained on
-- consecutive days and rested only at the end of the week, and a programme
-- written as "Day 1, 2, 4, 5" or "Mon/Wed/Fri" lost its rest days. This puts the
-- days back on the weekdays the source lists, and gives the splits without a
-- listed schedule the usual layout (3 days Mon/Wed/Fri, 4 days Mon/Tue/Thu/Fri).
--
-- It also folds days that were never workouts of their own (a warm-up, optional
-- accessory add-ons) into the real days, repeats the single-workout programmes
-- on the days per week they are meant to run, gives "to failure / AMRAP / max"
-- rows a real rep range instead of the 1-1 they were imported as, and fixes the
-- days-per-week, duration and category metadata to match.
--
-- Rows are matched on the catalog's SplitIds and on titles; anything that is no
-- longer in its imported shape (edited by an admin since) is left alone.

-- ---- helpers -----------------------------------------------------------------

-- Moves each day of p_splitid to p_newidx[k], k being its position by current
-- DayIndex. Skipped (with a notice) unless the split has exactly that many days.
CREATE FUNCTION pg_temp.reschedule(p_splitid uuid, p_newidx int[]) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF (SELECT count(*) FROM dbo.splitdays WHERE splitid = p_splitid) <> cardinality(p_newidx) THEN
        RAISE NOTICE 'split % skipped: day count is not %', p_splitid, cardinality(p_newidx);
        RETURN;
    END IF;
    -- Two steps so no row ever collides with uq_splitdays_splitdayindex.
    UPDATE dbo.splitdays SET dayindex = dayindex + 100 WHERE splitid = p_splitid;
    UPDATE dbo.splitdays d
    SET dayindex = p_newidx[o.rn]
    FROM (SELECT splitdayid, row_number() OVER (ORDER BY dayindex) AS rn
          FROM dbo.splitdays WHERE splitid = p_splitid) o
    WHERE d.splitdayid = o.splitdayid;
END $$;

-- Appends the exercises of day p_from to day p_into, re-points any logged
-- sessions at p_into and deletes p_from.
CREATE FUNCTION pg_temp.fold_day(p_splitid uuid, p_from text, p_into text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_from uuid;
    v_into uuid;
BEGIN
    SELECT splitdayid INTO v_from FROM dbo.splitdays WHERE splitid = p_splitid AND title = p_from;
    SELECT splitdayid INTO v_into FROM dbo.splitdays WHERE splitid = p_splitid AND title = p_into;
    IF v_from IS NULL OR v_into IS NULL THEN
        RAISE NOTICE 'split % skipped: no day "%" or "%"', p_splitid, p_from, p_into;
        RETURN;
    END IF;
    UPDATE dbo.splitdayexercises
    SET splitdayid = v_into,
        sortorder = sortorder + (SELECT COALESCE(MAX(sortorder), 0) FROM dbo.splitdayexercises WHERE splitdayid = v_into)
    WHERE splitdayid = v_from;
    UPDATE dbo.workoutsessions SET splitdayid = v_into WHERE splitdayid = v_from;
    DELETE FROM dbo.splitdays WHERE splitdayid = v_from;
END $$;

-- Copies day p_fromidx (and its exercises) to the empty slot p_toidx.
CREATE FUNCTION pg_temp.repeat_day(p_splitid uuid, p_fromidx int, p_toidx int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_from uuid;
    v_new uuid := gen_random_uuid();
BEGIN
    SELECT splitdayid INTO v_from FROM dbo.splitdays WHERE splitid = p_splitid AND dayindex = p_fromidx;
    IF v_from IS NULL OR EXISTS (SELECT 1 FROM dbo.splitdays WHERE splitid = p_splitid AND dayindex = p_toidx) THEN
        RAISE NOTICE 'split % skipped: cannot repeat day % on day %', p_splitid, p_fromidx, p_toidx;
        RETURN;
    END IF;
    INSERT INTO dbo.splitdays (splitdayid, splitid, dayindex, title, focuslabel, estimatedminutes, isrestday, sourcenotes)
    SELECT v_new, splitid, p_toidx, title, focuslabel, estimatedminutes, isrestday, sourcenotes
    FROM dbo.splitdays WHERE splitdayid = v_from;
    INSERT INTO dbo.splitdayexercises (splitdayid, exerciseid, sortorder, targetsets, targetrepslow, targetrepshigh, sourcesets, sourcereps)
    SELECT v_new, exerciseid, sortorder, targetsets, targetrepslow, targetrepshigh, sourcesets, sourcereps
    FROM dbo.splitdayexercises WHERE splitdayid = v_from;
END $$;

-- ---- broken days -------------------------------------------------------------

-- 6 Week Military-Style Conditioning: the dynamic warm-up was imported as its
-- own Monday workout, pushing Day 1-5 onto Tue-Sat. It becomes a note on each day.
UPDATE dbo.splitdays
SET sourcenotes = 'Warm-up before every session: 20 push-ups, 20 deep bodyweight squats, '
               || '10 lying windshield wipers each side, 20 long-stride walking lunges, 10 inverted rows, '
               || '10 jump squats, 10 side lunges each side.'
               || COALESCE(E'\n' || NULLIF(sourcenotes, ''), '')
WHERE splitid = '179630d9-1d33-4fef-bc6c-f7ea59398141'
  AND title LIKE 'Day %'
  AND EXISTS (SELECT 1 FROM dbo.splitdays w
              WHERE w.splitid = '179630d9-1d33-4fef-bc6c-f7ea59398141' AND w.title = 'Dynamic Warm-Up');
UPDATE dbo.workoutsessions
SET splitdayid = (SELECT splitdayid FROM dbo.splitdays
                  WHERE splitid = '179630d9-1d33-4fef-bc6c-f7ea59398141' AND title = 'Day 1: Speed and Agility')
WHERE splitdayid = (SELECT splitdayid FROM dbo.splitdays
                    WHERE splitid = '179630d9-1d33-4fef-bc6c-f7ea59398141' AND title = 'Dynamic Warm-Up');
DELETE FROM dbo.splitdayexercises
WHERE splitdayid = (SELECT splitdayid FROM dbo.splitdays
                    WHERE splitid = '179630d9-1d33-4fef-bc6c-f7ea59398141' AND title = 'Dynamic Warm-Up');
DELETE FROM dbo.splitdays
WHERE splitid = '179630d9-1d33-4fef-bc6c-f7ea59398141' AND title = 'Dynamic Warm-Up';
-- Its "NxA-B" rows were imported as 1 rep; the optional conditioning day is 3 rounds.
UPDATE dbo.splitdayexercises x
SET targetrepslow  = substring(x.sourcesets::text COLLATE "C" from '^\d+x(\d+)')::smallint,
    targetrepshigh = COALESCE(substring(x.sourcesets::text COLLATE "C" from '^\d+x\d+-(\d+)$'),
                              substring(x.sourcesets::text COLLATE "C" from '^\d+x(\d+)'))::smallint
FROM dbo.splitdays d
WHERE d.splitdayid = x.splitdayid
  AND d.splitid = '179630d9-1d33-4fef-bc6c-f7ea59398141'
  AND x.targetrepslow = 1 AND x.targetrepshigh = 1
  AND x.sourcesets::text COLLATE "C" ~ '^\d+x\d+(-\d+)?$';
UPDATE dbo.splitdayexercises x
SET targetsets = 3, sourcesets = '3-5 rounds'
FROM dbo.splitdays d
WHERE d.splitdayid = x.splitdayid
  AND d.splitid = '179630d9-1d33-4fef-bc6c-f7ea59398141'
  AND d.title = 'Day 5: Optional Full Body Conditioning'
  AND x.targetsets = 1;

-- Women's 3-Day Glute Building: the two short accessory workouts were imported
-- as days 4 and 5 (five days in a row); they finish workouts 1 and 2 instead.
-- The 100-rep hip thrust challenge is 5 x 20.
SELECT pg_temp.fold_day('91b52b2f-3503-49c9-9f93-ea7a5ba1b886', 'Accessory Workout 1', 'Full-Body Workout 1');
SELECT pg_temp.fold_day('91b52b2f-3503-49c9-9f93-ea7a5ba1b886', 'Accessory Workout 2', 'Full-Body Workout 2');
UPDATE dbo.splitdays
SET sourcenotes = 'Finish with the accessory work: as many hip thrusts as you can, resting briefly on failure '
               || 'and continuing until you reach 100 total reps.'
WHERE splitid = '91b52b2f-3503-49c9-9f93-ea7a5ba1b886' AND title = 'Full-Body Workout 1' AND sourcenotes IS NULL;
UPDATE dbo.splitdays
SET sourcenotes = 'Finish with the accessory work. No band? Use your bodyweight, a dumbbell or a barbell for the good mornings.'
WHERE splitid = '91b52b2f-3503-49c9-9f93-ea7a5ba1b886' AND title = 'Full-Body Workout 2' AND sourcenotes IS NULL;
UPDATE dbo.splitdayexercises x
SET targetrepslow = 20, targetrepshigh = 20
FROM dbo.splitdays d, dbo.exercises e
WHERE d.splitdayid = x.splitdayid AND e.exerciseid = x.exerciseid
  AND d.splitid = '91b52b2f-3503-49c9-9f93-ea7a5ba1b886'
  AND e.name = 'Bodyweight Hip Thrust' AND x.targetrepslow = 100;

-- 4 Day Upper/Lower Women's Dumbbell Only: the circuits are 2-3 rounds, not 1
-- set; the mini-circuits day is the optional extra on top of the 4 days.
UPDATE dbo.splitdayexercises x
SET targetsets = 3, sourcesets = '2-3 rounds'
FROM dbo.splitdays d
WHERE d.splitdayid = x.splitdayid
  AND d.splitid = '69ce7e71-e5cf-4c8e-8dd2-cb7fcb9f6d2e'
  AND d.title IN ('Upper Body Circuit', 'Lower Body Circuit')
  AND x.targetsets = 1;
UPDATE dbo.splitdays
SET title = 'Mini-Circuits (Optional)'
WHERE splitid = '69ce7e71-e5cf-4c8e-8dd2-cb7fcb9f6d2e' AND title = 'Mini-Circuits';

-- 6-Week Lean Bulk for Women: the conditioning circuit is 1-2 rounds.
UPDATE dbo.splitdayexercises x
SET targetsets = 2
FROM dbo.splitdays d
WHERE d.splitdayid = x.splitdayid
  AND d.splitid = 'fd31d957-36f8-4f6a-9186-663e520c2270'
  AND d.title = 'Day 6: Full Body Conditioning Circuit'
  AND x.targetsets = 1 AND x.sourcesets = '1-2';

-- Single-day imports titled after the page section they were parsed from.
UPDATE dbo.splitdays SET title = 'Glute Workout'
WHERE splitid = '2f1cfcf6-4c88-4700-8215-31f928edd282' AND title = 'Workout Notes';
UPDATE dbo.splitdays SET title = 'Kettlebell Ab & Core Circuit'
WHERE splitid = '50f3e7d2-85ee-4b79-b2b5-a05288124e3a' AND title = 'Workout Instructions';

-- 4 Week Kettlebell Ab & Core: one circuit, 3 rounds, Mon/Wed/Fri.
UPDATE dbo.splitdayexercises x
SET targetsets = 3, sourcesets = '3 rounds'
FROM dbo.splitdays d
WHERE d.splitdayid = x.splitdayid
  AND d.splitid = '50f3e7d2-85ee-4b79-b2b5-a05288124e3a'
  AND x.targetsets = 1;
SELECT pg_temp.repeat_day('50f3e7d2-85ee-4b79-b2b5-a05288124e3a', 1, 3);
SELECT pg_temp.repeat_day('50f3e7d2-85ee-4b79-b2b5-a05288124e3a', 1, 5);

-- Bodyweight Muscle Building: two workouts alternated 4 days a week (A/B rest A/B).
SELECT pg_temp.repeat_day('1fb445c9-6536-4561-afca-774673f8c10c', 1, 4);
SELECT pg_temp.repeat_day('1fb445c9-6536-4561-afca-774673f8c10c', 2, 5);

-- ---- placeholder reps --------------------------------------------------------

-- "Failure", "MAX", "AMRAP" and timed holds were imported as 1-1 reps. Holds go
-- in seconds, like the other Plank rows.
UPDATE dbo.splitdayexercises x
SET targetrepslow = v.lo, targetrepshigh = v.hi
FROM (VALUES
    ('60f282bd-db06-4268-b9c9-fbab3f9a663f'::uuid, 'Push-Up',                                  10, 20),
    ('3c4f58bb-b9a1-4db6-881b-30821f0703d4'::uuid, 'Plank',                                    60, 60),
    ('ad0d25f2-8b02-44e4-b5ff-4f0d6dbd06a1'::uuid, 'Plank',                                    60, 60),
    ('ad0d25f2-8b02-44e4-b5ff-4f0d6dbd06a1'::uuid, 'Decline Sit Up',                           10, 20),
    ('ad0d25f2-8b02-44e4-b5ff-4f0d6dbd06a1'::uuid, 'Wide Grip Pull Up',                         5, 12),
    ('ad0d25f2-8b02-44e4-b5ff-4f0d6dbd06a1'::uuid, 'Horizontal Leg Raise',                     10, 20),
    ('c0641f95-5112-4a59-af8b-395908b73ec0'::uuid, 'Push Ups (any variation)',                 10, 20),
    ('c0641f95-5112-4a59-af8b-395908b73ec0'::uuid, 'Calf Raise (any variation)',               15, 25),
    ('c0641f95-5112-4a59-af8b-395908b73ec0'::uuid, 'Box Squat OR Step Up (controlled tempo)',  10, 20),
    ('2f1cfcf6-4c88-4700-8215-31f928edd282'::uuid, 'Leg Extension',                            12, 20),
    ('9dbc608f-fdd4-45b0-be49-13852e9f66e9'::uuid, 'Plank',                                    60, 90)
) AS v(splitid, exercise, lo, hi), dbo.splitdays d, dbo.exercises e
WHERE d.splitdayid = x.splitdayid AND e.exerciseid = x.exerciseid
  AND d.splitid = v.splitid AND e.name = v.exercise
  AND x.targetrepslow = 1 AND x.targetrepshigh = 1;

-- 6 Day Push/Pull/Legs was imported with sets only, every rep target 1-1. Each
-- day is a powerbuilding layout: a main lift for 5 x 5, one back-off set at 20%
-- less weight for as many reps as possible, two 3-set compounds in the
-- hypertrophy range, then 5-set accessories at higher reps.
UPDATE dbo.splitdayexercises x
SET targetrepslow  = CASE WHEN e.name LIKE '%(Use 20\% less weight%' THEN 8
                          WHEN x.sortorder = 1 THEN 5
                          WHEN x.targetsets = 3 THEN 8
                          WHEN e.name LIKE 'Calf Raise%' THEN 12
                          ELSE 10 END,
    targetrepshigh = CASE WHEN e.name LIKE '%(Use 20\% less weight%' THEN 12
                          WHEN x.sortorder = 1 THEN 5
                          WHEN x.targetsets = 3 THEN 10
                          WHEN e.name LIKE 'Calf Raise%' THEN 20
                          ELSE 15 END
FROM dbo.splitdays d, dbo.exercises e
WHERE d.splitdayid = x.splitdayid AND e.exerciseid = x.exerciseid
  AND d.splitid = 'fc73dff1-31dd-4e61-a0b2-31297abcf729'
  AND x.targetrepslow = 1 AND x.targetrepshigh = 1;
UPDATE dbo.splitdays
SET sourcenotes = 'Work up to 5 heavy sets of 5 on the first lift, then drop the weight by 20% '
               || 'and do one back-off set for as many reps as you can. Rest 2-3 minutes between '
               || 'heavy sets and 60-90 seconds on the accessories.'
WHERE splitid = 'fc73dff1-31dd-4e61-a0b2-31297abcf729' AND COALESCE(sourcenotes, '') = '';

-- 6 Week Military-Style Conditioning: the supersets and conditioning pieces had
-- no sets or reps in the source. Sprints, runs and carries count one effort per
-- set (1 rep); holds and carries by time are in seconds, like Plank elsewhere.
UPDATE dbo.splitdayexercises x
SET targetsets = v.sets, targetrepslow = v.lo, targetrepshigh = v.hi
FROM (VALUES
    ('Day 1: Speed and Agility',                 'Sprints (at least 20 yards)',                                  6,  1,  1),
    ('Day 1: Speed and Agility',                 'Timed shuttle run (at least 10 yards)',                        3,  1,  1),
    ('Day 1: Speed and Agility',                 'Superset: Dumbbell Shrug & Hyperextension',                    2, 12, 15),
    ('Day 1: Speed and Agility',                 'Superset: Floor Crunch & Bent-Knee Hanging Leg Raise',         2, 12, 15),
    ('Day 2: Power',                             'Explosive Single Arm Dumbbell or Kettlebell Flat Bench Press', 2,  6,  8),
    ('Day 2: Power',                             '3-Way Plank: alternate from side, middle to other side without rest (10sec each)', 2, 30, 30),
    ('Day 2: Power',                             'Sprint Intervals: total of 8 sprints with one minute rests',   8,  1,  1),
    ('Day 3: Strength',                          'Superset: Inverted or TRX Row & Plyo Push-Up',                 2,  8, 12),
    ('Day 3: Strength',                          'Superset: Hanging Leg Raise & Planks',                         2, 10, 15),
    ('Day 4: Hypertrophy & Muscular Endurance',  'Superset: Feet-Elevated Push-Up & Single Leg Calf Raise',      2, 15, 20),
    ('Day 4: Hypertrophy & Muscular Endurance',  'Superset: Incline 3-Way Sit-Up & Lying Leg Raise',             2, 15, 20),
    ('Day 4: Hypertrophy & Muscular Endurance',  'Sled Pull or Drag or Farmer''s Walk',                           3, 30, 45)
) AS v(day, exercise, sets, lo, hi), dbo.splitdays d, dbo.exercises e
WHERE d.splitdayid = x.splitdayid AND e.exerciseid = x.exerciseid
  AND d.splitid = '179630d9-1d33-4fef-bc6c-f7ea59398141'
  AND d.title = v.day AND e.name = v.exercise
  AND x.targetrepslow = 1 AND x.targetrepshigh = 1;

-- Bodyweight Muscle Building: the finishing sprints are 2-5 all-out efforts; a
-- beginner programme starts at 3.
UPDATE dbo.splitdayexercises x
SET targetsets = 3
FROM dbo.splitdays d, dbo.exercises e
WHERE d.splitdayid = x.splitdayid AND e.exerciseid = x.exerciseid
  AND d.splitid = '1fb445c9-6536-4561-afca-774673f8c10c'
  AND e.name = 'Short All-Out Sprint Outdoors or on Treadmill'
  AND x.targetsets = 2;

-- 4 Day Upper/Lower Women's Dumbbell Only: the optional mini-circuit runs for 2
-- rounds of 20, a short add-on next to the 3-round main circuits.
UPDATE dbo.splitdayexercises x
SET targetsets = 2
FROM dbo.splitdays d
WHERE d.splitdayid = x.splitdayid
  AND d.splitid = '69ce7e71-e5cf-4c8e-8dd2-cb7fcb9f6d2e'
  AND d.title = 'Mini-Circuits (Optional)'
  AND x.targetsets = 1;

-- ---- rest days ---------------------------------------------------------------

-- Source lists the weekdays / day numbers.
SELECT pg_temp.reschedule('25b530fa-19b1-4e1d-82f1-63288f0144a9', '{1,2,4,5}');      -- P.H.U.L.
SELECT pg_temp.reschedule('3bf2fcc4-aeaf-4cd2-a0d8-fbb3a828fbbd', '{1,3,5}');        -- Dumbbell Only Full Body
SELECT pg_temp.reschedule('a662a628-e7b3-4213-817e-dbb1ca6dfd01', '{1,2,4,5}');      -- 10 Week Upper/Lower for Women
SELECT pg_temp.reschedule('3c4f58bb-b9a1-4db6-881b-30821f0703d4', '{1,2,3,5,6,7}');  -- 12 Week PPL for Women
SELECT pg_temp.reschedule('e6f54e77-bf97-4f93-a800-078f1f513365', '{1,2,4,5}');      -- Mass Building for Hardgainers
SELECT pg_temp.reschedule('4e751102-0401-4d50-86d0-a2fd34db09d8', '{1,2,3,5,6}');    -- 5 Day Powerbuilding
SELECT pg_temp.reschedule('5a87d14a-b795-4e9f-b670-71fe21a13e1f', '{1,2,4,5,6}');    -- 5 Day Women's Dumbbell Only
SELECT pg_temp.reschedule('fd31d957-36f8-4f6a-9186-663e520c2270', '{1,2,4,5,6}');    -- 6-Week Lean Bulk for Women
SELECT pg_temp.reschedule('f186215d-04d7-459e-a139-1ff50916b13b', '{1,2,4,5}');      -- 4 Week Upper/Lower & Abs
SELECT pg_temp.reschedule('0fdd5437-dad8-4f35-9d4e-ff1ecd7318cc', '{1,2,3,5,6}');    -- 5 Day Athletic Hypertrophy
SELECT pg_temp.reschedule('6e30afd5-dd02-48ad-aa63-36899af5b9e7', '{1,2,4,5}');      -- 4 Day Hero Physique
SELECT pg_temp.reschedule('3a16eb5b-48f8-415a-a2f5-4496879aeefa', '{1,2,4,6}');      -- 7 Day Lean Athlete
SELECT pg_temp.reschedule('9dbc608f-fdd4-45b0-be49-13852e9f66e9', '{1,2,4,6}');      -- 4 Day Strength & Power
SELECT pg_temp.reschedule('179630d9-1d33-4fef-bc6c-f7ea59398141', '{1,2,3,4,5}');    -- Military-Style Conditioning
SELECT pg_temp.reschedule('69ce7e71-e5cf-4c8e-8dd2-cb7fcb9f6d2e', '{1,2,4,5,6}');    -- 4 Day Upper/Lower Women's DB (+ optional Sat)
SELECT pg_temp.reschedule('91b52b2f-3503-49c9-9f93-ea7a5ba1b886', '{1,3,5}');        -- Women's 3-Day Glute Building

-- No schedule in the source: 3 days Mon/Wed/Fri.
SELECT pg_temp.reschedule('7407493e-f36b-1410-88dc-0092085e5b62', '{1,3,5}');        -- Full Body Circuit
SELECT pg_temp.reschedule('8d07493e-f36b-1410-88dc-0092085e5b62', '{1,3,5}');        -- Lean & Lift Full Body
SELECT pg_temp.reschedule('9c07493e-f36b-1410-88dc-0092085e5b62', '{1,3,5}');        -- Calisthenics Foundations
SELECT pg_temp.reschedule('ad0d25f2-8b02-44e4-b5ff-4f0d6dbd06a1', '{1,3,5}');        -- 3 Day Full Body Toning for Women
SELECT pg_temp.reschedule('ddbab1d3-6ceb-4fed-b7a6-a76da65ca731', '{1,3,5}');        -- 3 Day PPL for Beginners
SELECT pg_temp.reschedule('b90df28e-e579-4ba9-a541-def1c284e565', '{1,3,5}');        -- 8-Week Fat Loss 40+

-- No schedule in the source: 4 days Mon/Tue/Thu/Fri.
SELECT pg_temp.reschedule('6f07493e-f36b-1410-88dc-0092085e5b62', '{1,2,4,5}');      -- Upper / Lower Split
SELECT pg_temp.reschedule('7e07493e-f36b-1410-88dc-0092085e5b62', '{1,2,4,5}');      -- PHUL Power Hypertrophy
SELECT pg_temp.reschedule('9207493e-f36b-1410-88dc-0092085e5b62', '{1,2,4,5}');      -- Glute & Core Sculpt
SELECT pg_temp.reschedule('9707493e-f36b-1410-88dc-0092085e5b62', '{1,2,4,5}');      -- Powerlifting Strength Block
SELECT pg_temp.reschedule('6e9aff9f-cbc1-45a1-8a21-4149751672ab', '{1,2,4,5}');      -- 12 Week Upper/Lower Fat Loss
SELECT pg_temp.reschedule('d9d47dd2-a683-471d-a264-426102fa1dd1', '{1,2,4,5}');      -- Dumbbell Only 4 Day Upper/Lower
SELECT pg_temp.reschedule('d3d40d31-1eb2-4008-9e59-9c11fd94e5aa', '{1,2,4,5}');      -- 8-Week Muscle Building 40+
SELECT pg_temp.reschedule('c0641f95-5112-4a59-af8b-395908b73ec0', '{1,2,4,5}');      -- Lean & Strong for Women 40+
SELECT pg_temp.reschedule('b6ceec2a-fd06-42c9-975d-abaaa6ee2244', '{1,2,4,5}');      -- 8-Week Advanced Muscle Building for Women
SELECT pg_temp.reschedule('0b1cff43-b08c-4465-a7da-1fa81c31d958', '{1,2,4,5}');      -- 8 Week Beginner Fat Loss for Women
SELECT pg_temp.reschedule('2ab63cc4-291c-46b5-9276-c66a2c92e76a', '{1,2,4,5}');      -- 8 Week Mass Building Hypertrophy
SELECT pg_temp.reschedule('dd3bbd1d-70cb-4fbb-a7ee-a5db2025e958', '{1,2,4,5}');      -- 2-Week Deload

-- PHAT: Mon/Tue power, Thu-Sat hypertrophy. 2-day maintenance: Mon/Thu.
SELECT pg_temp.reschedule('8307493e-f36b-1410-88dc-0092085e5b62', '{1,2,4,5,6}');    -- PHAT Adaptive Training
SELECT pg_temp.reschedule('a107493e-f36b-1410-88dc-0092085e5b62', '{1,4}');          -- 2-Day Maintenance Full Body

-- ---- metadata ----------------------------------------------------------------

-- Training days per week (the original splits never had it; a few imports
-- counted optional days or the programme name).
UPDATE dbo.workoutsplits s
SET daysperweek = v.dpw
FROM (VALUES
    ('6a07493e-f36b-1410-88dc-0092085e5b62'::uuid, 6),  -- PPL Hypertrophy Protocol
    ('6f07493e-f36b-1410-88dc-0092085e5b62'::uuid, 4),  -- Upper / Lower Split
    ('7407493e-f36b-1410-88dc-0092085e5b62'::uuid, 3),  -- Full Body Circuit
    ('7907493e-f36b-1410-88dc-0092085e5b62'::uuid, 6),  -- Arnold Split
    ('7e07493e-f36b-1410-88dc-0092085e5b62'::uuid, 4),  -- PHUL Power Hypertrophy
    ('8307493e-f36b-1410-88dc-0092085e5b62'::uuid, 5),  -- PHAT Adaptive Training
    ('8807493e-f36b-1410-88dc-0092085e5b62'::uuid, 5),  -- Classic Bro Split
    ('1447483e-f36b-1410-88dc-0092085e5b62'::uuid, 5),  -- 5-Day Metabolic Circuit
    ('8d07493e-f36b-1410-88dc-0092085e5b62'::uuid, 3),  -- Lean & Lift Full Body
    ('9207493e-f36b-1410-88dc-0092085e5b62'::uuid, 4),  -- Glute & Core Sculpt
    ('9707493e-f36b-1410-88dc-0092085e5b62'::uuid, 4),  -- Powerlifting Strength Block
    ('9c07493e-f36b-1410-88dc-0092085e5b62'::uuid, 3),  -- Calisthenics Foundations
    ('a107493e-f36b-1410-88dc-0092085e5b62'::uuid, 2),  -- 2-Day Maintenance Full Body
    ('de75b9e7-ff52-49cc-bc27-a99f64181013'::uuid, 6),  -- 10 Week Women's Fat Loss (Mon-Fri + one weekend day)
    ('3a16eb5b-48f8-415a-a2f5-4496879aeefa'::uuid, 4)   -- 7 Day Lean Athlete
) AS v(splitid, dpw)
WHERE s.splitid = v.splitid;

-- "N-day program" counts the authored days.
UPDATE dbo.workoutsplits s
SET durationdays = v.days
FROM (VALUES
    ('91b52b2f-3503-49c9-9f93-ea7a5ba1b886'::uuid, 3),  -- Women's 3-Day Glute Building
    ('50f3e7d2-85ee-4b79-b2b5-a05288124e3a'::uuid, 3),  -- Kettlebell Ab & Core
    ('1fb445c9-6536-4561-afca-774673f8c10c'::uuid, 4),  -- Bodyweight Muscle Building
    ('179630d9-1d33-4fef-bc6c-f7ea59398141'::uuid, 5)   -- Military-Style Conditioning
) AS v(splitid, days)
WHERE s.splitid = v.splitid;

-- Categories (and the category-derived hero image 0006 gave them).
UPDATE dbo.workoutsplits
SET category = 'PushPullLegs',
    heroimageurl = CASE WHEN heroimageurl = 'asset:splits/bro_split' THEN 'asset:splits/push_pull_legs' ELSE heroimageurl END
WHERE splitid = '3c4f58bb-b9a1-4db6-881b-30821f0703d4' AND category = 'BroSplit';   -- 12 Week PPL for Women
UPDATE dbo.workoutsplits
SET category = 'UpperLower',
    heroimageurl = CASE WHEN heroimageurl = 'asset:splits/bro_split' THEN 'asset:splits/upper_lower' ELSE heroimageurl END
WHERE splitid = 'dd3bbd1d-70cb-4fbb-a7ee-a5db2025e958' AND category = 'BroSplit';   -- 2-Week Deload

-- 15-Minute Warm-Up Routines are warm-ups, not a training split: off the public
-- catalogue. Anyone running it keeps it (and can still open it) through an
-- assignment.
INSERT INTO dbo.splitassignments (splitid, userid)
SELECT uas.splitid, uas.userid
FROM dbo.useractivesplits uas
WHERE uas.splitid = '7b693187-2c4a-4a23-b110-cc929a76e5a8'
ON CONFLICT DO NOTHING;
UPDATE dbo.workoutsplits
SET issystemdefault = false, visibility = 'Private'
WHERE splitid = '7b693187-2c4a-4a23-b110-cc929a76e5a8';
