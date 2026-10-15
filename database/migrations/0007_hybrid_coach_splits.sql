-- Three catalog splits built from a coach's group-training programme (Jun-Sep
-- 2026): Hybrid Strength & Conditioning blocks I-III. Each training week is
-- Mon Hinge & Shoulders / Wed Upper / Fri Lower, plus a Sunday team WOD.
--
-- The split model only stores sets x reps, so circuit formats (AMRAP, EMOM,
-- I-go-you-go, ladders) are approximated: rounds become sets, time-based work
-- is in seconds (as the seeded Plank rows are), and the coach's original format
-- is kept in splitdays.sourcenotes / splitdayexercises.sourcereps. Warm-ups are
-- left out of the logged exercises and summarised in sourcenotes.
--
-- Exercises the catalog lacks are added as system exercises first; everything
-- else resolves by name against the system catalog (createdbyuserid IS NULL).

INSERT INTO dbo.exercises (name, musclegroup, equipmenttype, iscompound)
SELECT v.name, v.musclegroup, v.equipmenttype, v.iscompound
FROM (VALUES
    ('Rack Pull',                     'back',      'Barbell',    true),
    ('Cossack Squat',                 'legs',      'Kettlebell', true),
    ('Single Arm Kettlebell Deadlift','legs',      'Kettlebell', true),
    ('Row Erg',                       'back',      'Machine',    true),
    ('Ski Erg',                       'back',      'Machine',    true),
    ('Assault Bike',                  'legs',      'Machine',    true),
    ('Run',                           'legs',      'Bodyweight', true),
    ('Hollow Rock',                   'core',      'Bodyweight', false),
    ('Suitcase Carry',                'core',      'Kettlebell', true),
    ('Sumo Deadlift High Pull',       'back',      'Kettlebell', true),
    ('Barbell High Pull',             'shoulders', 'Barbell',    true),
    ('Landmine Row',                  'back',      'Barbell',    true),
    ('Single Arm Landmine Row',       'back',      'Barbell',    true),
    ('High Knees',                    'legs',      'Bodyweight', false),
    ('Hand-Release Push-Up',          'chest',     'Bodyweight', true),
    ('Deficit Push-Up',               'chest',     'Bodyweight', true),
    ('Plank Pass-Through',            'core',      'Dumbbell',   false),
    ('Devil Press',                   'shoulders', 'Dumbbell',   true),
    ('Gorilla Row',                   'back',      'Kettlebell', true),
    ('Wall Walk',                     'shoulders', 'Bodyweight', true),
    ('Toes-to-Bar',                   'core',      'Bodyweight', false),
    ('V-Up',                          'core',      'Bodyweight', false),
    ('Double Kettlebell Front Squat', 'legs',      'Kettlebell', true),
    ('Plank Toe Touch',               'core',      'Bodyweight', false)
) AS v(name, musclegroup, equipmenttype, iscompound)
WHERE NOT EXISTS (SELECT 1 FROM dbo.exercises e
                  WHERE e.name = v.name AND e.createdbyuserid IS NULL);

-- Fails the migration (rolling it all back) on a misspelt exercise name rather
-- than silently dropping the row.
CREATE FUNCTION pg_temp.ex(p_name text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
    v_id uuid;
BEGIN
    SELECT exerciseid INTO v_id
    FROM dbo.exercises
    WHERE name = p_name AND createdbyuserid IS NULL
    ORDER BY createdatutc, exerciseid
    LIMIT 1;
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'exercise not in catalog: %', p_name;
    END IF;
    RETURN v_id;
END $$;

CREATE FUNCTION pg_temp.day(
    p_splitid uuid, p_dayindex int, p_title text, p_focus text, p_minutes int, p_notes text
) RETURNS uuid LANGUAGE sql AS $$
    INSERT INTO dbo.splitdays (splitid, dayindex, title, focuslabel, estimatedminutes, isrestday, sourcenotes)
    VALUES (p_splitid, p_dayindex, p_title, p_focus, p_minutes, false, p_notes)
    RETURNING splitdayid;
$$;

-- p_items: one row per exercise, in order: name | sets | reps low | reps high | coach's reps.
CREATE FUNCTION pg_temp.exercises(p_dayid uuid, p_items text[]) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    i int;
    f text[];
BEGIN
    FOR i IN 1 .. array_length(p_items, 1) LOOP
        f := string_to_array(p_items[i], '|');
        INSERT INTO dbo.splitdayexercises
            (splitdayid, exerciseid, sortorder, targetsets, targetrepslow, targetrepshigh, sourcesets, sourcereps)
        VALUES (p_dayid, pg_temp.ex(btrim(f[1])), i,
                btrim(f[2])::smallint, btrim(f[3])::smallint, btrim(f[4])::smallint,
                btrim(f[2]), NULLIF(btrim(f[5]), ''));
    END LOOP;
END $$;

INSERT INTO dbo.workoutsplits
    (splitid, name, category, level, durationdays, description, heroimageurl, issystemdefault, sortorder,
     recommendedgoal, visibility, fulldescription, daysperweek, programdurationweeks,
     minsessionminutes, maxsessionminutes, equipmentrequired, targetgender, workouttypelabel, sourcecategoriesjson)
VALUES
    ('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a01', 'Hybrid Strength & Conditioning I', 'FullBody', 'Intermediate', 14,
     'A 2-week hybrid block: heavy hinge, press and squat days with a conditioning finisher, plus a Sunday kettlebell team WOD. 4 days a week, about 60 minutes.',
     'asset:splits/conditioning', true, 14, 'MaintainActive', 'Public',
     'Mon: Hinge & Shoulders. Wed: Upper (press + pull). Fri: Lower. Sun: Team WOD. Every session opens with a 3-round warm-up (1 min on a machine plus two mobility or activation drills), then a strength block, an accessory superset and a 12-15 minute conditioning finisher. Finisher sets are rounds of a circuit; time-based work is in seconds.',
     4, 2, 45, 60, 'Barbell, Dumbbells, Kettlebells, Plyo Box, Bands, Rower, Air Bike', 'Male & Female', 'Hybrid',
     '["Hybrid","Conditioning","Strength"]'),
    ('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a02', 'Hybrid Strength & Conditioning II', 'FullBody', 'Intermediate', 14,
     'Block II of the hybrid programme: deadlifts and swings, bench and incline with heavy rows, squat and glute work, and team conditioning on Sundays. 4 days a week, about 60 minutes.',
     'asset:splits/conditioning', true, 15, 'MaintainActive', 'Public',
     'Mon: Hinge & Shoulders. Wed: Upper (press + pull). Fri: Lower. Sun: Team WOD. Every session opens with a 3-round warm-up, then a strength block, an accessory superset and an EMOM, AMRAP or interval finisher. Finisher sets are rounds of a circuit; time-based work is in seconds.',
     4, 2, 45, 60, 'Barbell, Dumbbells, Kettlebells, Landmine, Plyo Box, Pull-Up Bar, Rower, Ski Erg, Air Bike', 'Male & Female', 'Hybrid',
     '["Hybrid","Conditioning","Strength"]'),
    ('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a03', 'Hybrid Strength & Conditioning III', 'FullBody', 'Intermediate', 7,
     'The latest hybrid week: deadlift and row intervals, close-grip bench with pull-ups, back squats with box jumps, and a 90-second interval team WOD on Sunday. 4 days a week, about 60 minutes.',
     'asset:splits/conditioning', true, 16, 'MaintainActive', 'Public',
     'Mon: Hinge & Shoulders. Wed: Upper (press + pull). Fri: Lower. Sun: Team WOD. Every session opens with 1 minute on a machine plus two warm-up drills, then a strength block, an accessory superset and a short conditioning finisher. Finisher sets are rounds of a circuit; time-based work is in seconds.',
     4, 1, 45, 60, 'Barbell, Dumbbells, Kettlebells, Plyo Box, Pull-Up Bar, Rower, Ski Erg, Wall Ball', 'Male & Female', 'Hybrid',
     '["Hybrid","Conditioning","Strength"]');

-- ---- Block I --------------------------------------------------------------
SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a01', 1,
    'Hinge & Shoulders: Rack Pull', 'Strength + Conditioning', 55,
    'Warm-up: 1 min row, 3 Jefferson curls, 10 band pull-downs. Strength: 6 rounds of 8 heavy rack pulls. Accessory: 3 rounds of 10 strict press, 12 full circles, 14 band face pulls. Finisher: 12 min of 30 s bike sprint, 6+6 weighted Cossack squats, 12 Russian twists.'), ARRAY[
    'Rack Pull              | 6 | 8  | 8  | 8 heavy',
    'Barbell Shoulder Press | 3 | 10 | 10 | 10 strict',
    'Face Pull              | 3 | 14 | 14 | 14 band',
    'Assault Bike           | 4 | 30 | 30 | 30 sec sprint',
    'Cossack Squat          | 4 | 12 | 12 | 6+6 weighted',
    'Russian Twist          | 4 | 12 | 12 | 12 total']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a01', 3,
    'Upper: Bench & Upright Row', 'Strength + Conditioning', 60,
    'Warm-up: 3 rounds of 1 min bike, 10 band face pulls, 10 light DB press each arm. Strength: 6 rounds of 6 bench press + 12 KB upright rows. Accessory: 3 rounds of 8 DB bent-over rows each arm + 10-12 low-bar pull-ups. Finisher: 12-15 min AMRAP of 45 s row, 15 squats, 15 anchored sit-ups, 15 light RDLs.'), ARRAY[
    'Bench Press            | 6 | 6  | 6  | 6',
    'Upright Row            | 6 | 12 | 12 | 12 KB',
    'Dumbbell Bent Over Row | 3 | 8  | 8  | 8 each arm',
    'Inverted Row           | 3 | 10 | 12 | 10-12 low-bar pull-ups',
    'Row Erg                | 4 | 45 | 45 | 45 sec',
    'Bodyweight Squat       | 4 | 15 | 15 | 15',
    'Sit Up                 | 4 | 15 | 15 | 15 anchored feet',
    'Romanian Deadlift      | 4 | 15 | 15 | 15 light']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a01', 5,
    'Lower: Tempo Squat & Triceps', 'Strength + Conditioning', 55,
    'Warm-up: 3 rounds of 1 min bike, 30 s reverse plank hold, 30 s wall sit. Strength: 6 rounds of 6 tempo back squats (3 s down, explosive up). Accessory: 3 rounds of 12-15 dips between two boxes + 12-15 bench triceps push. Finisher: 12 min of 10 s sprint run, 6-8 DB floor press, 8-10 hand-release push-ups, 10 plank DB pass-throughs.'), ARRAY[
    'Barbell Back Squat     | 6 | 6  | 6  | 6 tempo: 3 sec down, explosive up',
    'Dips                   | 3 | 12 | 15 | 12-15 on two boxes',
    'Bench Dips             | 3 | 12 | 15 | 12-15 hands on bench',
    'Sprint                 | 4 | 10 | 10 | 10 sec sprint run',
    'Dumbbell Floor Press   | 4 | 6  | 8  | 6-8',
    'Hand-Release Push-Up   | 4 | 8  | 10 | 8-10',
    'Plank Pass-Through     | 4 | 10 | 10 | 10 DB pass-through']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a01', 7,
    'Team WOD: Kettlebell Ladder', 'Team Conditioning', 50,
    'Team of two. Two 20-minute blocks, I-go-you-go or AMRAP, alternating arms each round. Block 1: 10 single-arm deadlifts (weight between the feet), 9 single-arm ground-to-overhead, 8 single-arm front-rack squats, 7 V-ups. Rest. Block 2: 10 KB swings, 9 side KB abs each side, 8 overhead walking lunges (4 L + 4 R), 7 KB squat cleans.'), ARRAY[
    'Single Arm Kettlebell Deadlift | 5 | 10 | 10 | 10, alternate arms each round',
    'Dumbbell Clean and Press       | 5 | 9  | 9  | 9 ground-to-overhead, one arm',
    'Kettlebell Goblet Squat        | 5 | 8  | 8  | 8, KB on the shoulder, one arm',
    'V-Up                           | 5 | 7  | 7  | 7',
    'Kettlebell Swing               | 5 | 10 | 10 | 10',
    'Side Bends                     | 5 | 9  | 9  | 9 each side with KB',
    'Overhead Walking Lunge         | 5 | 8  | 8  | 4 L + 4 R',
    'Kettlebell Goblet Squat        | 5 | 7  | 7  | 7 KB squat cleans']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a01', 8,
    'Hinge & Shoulders: DB RDL & Pull', 'Strength + Conditioning', 60,
    'Warm-up: 3 rounds of 1 min machine, 1 length elephant walk, 12 straight-arm band pull-downs. Strength: 4 rounds of 12 DB RDLs (3-5 s down) + 8-12 low-bar pull-ups. Accessory: 3 rounds of 8-10 seated DB press, 12-15 lateral raises, 12-15 DB flys. Finisher: 12 min AMRAP of 12 jump lunges, 12 cal bike, 12 walking lunges, 12 cal row.'), ARRAY[
    'Dumbbell Romanian Deadlift     | 4 | 12 | 12 | 12, 3-5 sec down',
    'Inverted Row                   | 4 | 8  | 12 | 8-12 low-bar pull-ups',
    'Seated Dumbbell Shoulder Press | 3 | 8  | 10 | 8-10',
    'Dumbbell Lateral Raise         | 3 | 12 | 15 | 12-15',
    'Dumbbell Chest Fly             | 3 | 12 | 15 | 12-15 on bench',
    'Jump Lunges                    | 4 | 12 | 12 | 12',
    'Assault Bike                   | 4 | 12 | 12 | 12 cal',
    'Walking Lunge                  | 4 | 12 | 12 | 12',
    'Row Erg                        | 4 | 12 | 12 | 12 cal']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a01', 10,
    'Upper: Bench & Dips', 'Strength + Conditioning', 60,
    'Warm-up: 3 rounds of 1 min ski, 10 walking lunges, 1 length inchworm. Strength: 4 rounds of 6 bench press + 12 dips on one box behind. Accessory: 3 rounds of 10-12 DB bent-over rows + 12-15 TRX inverted rows. Finisher: 15 min of 15 cal row, 20 jump squats, 20 back-step lunges, 20 diagonal V-ups.'), ARRAY[
    'Bench Press            | 4 | 6  | 6  | 6',
    'Bench Dips             | 4 | 12 | 12 | 12 on one box behind',
    'Dumbbell Bent Over Row | 3 | 10 | 12 | 10-12 both DBs',
    'Inverted Row           | 3 | 12 | 15 | 12-15 TRX',
    'Row Erg                | 3 | 15 | 15 | 15 cal',
    'Jump Squat             | 3 | 20 | 20 | 20',
    'Reverse Lunge          | 3 | 20 | 20 | 20 back-step lunges',
    'V-Up                   | 3 | 20 | 20 | 20 diagonal, total']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a01', 12,
    'Lower: Goblet Squat & Triceps', 'Strength + Conditioning', 55,
    'Warm-up: 3 rounds of 1 min run, 10 single-leg glute bridges, 30 s wall sit. Strength: 5-6 rounds of 12 DB goblet squats (17-22 kg). Accessory: 3 rounds of 12-15 box dips in front + 12-15 barbell triceps press. Finisher: 15 min of 12 cal row, 10 leg raises, 8 burpees, 6 push-ups.'), ARRAY[
    'Dumbbell Goblet Squat  | 6 | 12 | 12 | 12, 17-22 kg, 5-6 rounds',
    'Bench Dips             | 3 | 12 | 15 | 12-15 box in front',
    'Skull Crushers         | 3 | 12 | 15 | 12-15 barbell triceps press',
    'Row Erg                | 4 | 12 | 12 | 12 cal',
    'Lying Leg Raise        | 4 | 10 | 10 | 10',
    'Burpees                | 4 | 8  | 8  | 8',
    'Push-Up                | 4 | 6  | 6  | 6']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a01', 14,
    'Team WOD: 100-Rep EMOM', 'Team Conditioning', 50,
    'Every minute: do the first movement, then the second until the minute ends, until 100 reps of the second are banked. Rest as needed between pairs. 1) 10 box jump-overs + SDHP (barbell, or KB). 2) 10 half burpees + squats, standing up with the opposite hand to the extended leg. 3) 10 KB swings + gorilla rows. 4) 40 jump ropes + plank toe touches (100 each side). Can''t keep the pace? Do it as a 10-minute AMRAP of 10 reps each (40 on the rope).'), ARRAY[
    'Box Jump                | 10 | 10 | 10 | 10 jump-overs on the minute',
    'Sumo Deadlift High Pull | 10 | 10 | 10 | rest of the minute, 100 total',
    'Burpees                 | 10 | 10 | 10 | 10 half burpees on the minute',
    'Bodyweight Squat        | 10 | 10 | 10 | rest of the minute, 100 total',
    'Kettlebell Swing        | 10 | 10 | 10 | 10 on the minute',
    'Gorilla Row             | 10 | 10 | 10 | rest of the minute, 100 total',
    'Jump Rope               | 10 | 40 | 40 | 40 on the minute',
    'Plank Toe Touch         | 10 | 10 | 10 | rest of the minute, 100 each side']);

-- ---- Block II -------------------------------------------------------------
SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a02', 1,
    'Hinge & Shoulders: Deadlift & Swings', 'Strength + Conditioning', 55,
    'Warm-up: 3 min machine, then 3 rounds of 10 plank DB rows, 10 alternating lunges with twist. Strength: 4 rounds of 8 deadlifts + 8 one-arm swings each arm. Accessory: 3 rounds of 10 one-arm supported press + 12-15 seated DB side raises. Finisher: 3-4 rounds of 1 min row, 25 SDHP, 1 min weighted march.'), ARRAY[
    'Deadlift                  | 4 | 8  | 8  | 8',
    'Kettlebell Swing          | 4 | 8  | 8  | 8 one-arm, each arm',
    'Single Arm Dumbbell Press | 3 | 10 | 10 | 10 supported',
    'Seated Lateral Raise      | 3 | 12 | 15 | 12-15',
    'Row Erg                   | 4 | 60 | 60 | 1 min',
    'Sumo Deadlift High Pull   | 4 | 25 | 25 | 25']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a02', 3,
    'Upper: Bench & High Pull', 'Strength + Conditioning', 55,
    'Warm-up: 3 rounds of 1 min machine, 10 windmills each side, 10 TRX face pulls. Strength: 5 rounds of 5 bench press (slow lowering) + 12 barbell high pulls. Accessory: 3 rounds of 8-12 bench-supported landmine rows + 8-12 landmine rows. Finisher: 12 cal row, 10 jump lunges, 40 high knees, 10 weighted ab-mat sit-ups.'), ARRAY[
    'Bench Press                              | 5 | 5  | 5  | 5, slow down',
    'Barbell High Pull                        | 5 | 12 | 12 | 12',
    'Single Arm Landmine Row                  | 3 | 8  | 12 | 8-12 bench-supported',
    'Landmine Row                             | 3 | 8  | 12 | 8-12',
    'Row Erg                                  | 3 | 12 | 12 | 12 cal',
    'Jump Lunges                              | 3 | 10 | 10 | 10',
    'High Knees                               | 3 | 40 | 40 | 40',
    'Weighted Sit Up (with dumbbell on chest) | 3 | 10 | 10 | 10 on ab mat']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a02', 5,
    'Lower: DB Squats & Push', 'Strength + Conditioning', 60,
    'Warm-up: 3 rounds of 30 s fast bike, 30 s rest. Strength: 3 rounds of 20 DB squats (add weight once all reps are done). Accessory: 3 rounds of 12 single-leg glute bridges each side + 8-12 close-feet air squats, then 3 rounds of 12 dips + 12 deficit push-ups. Finisher: 20 min EMOM rotating 1 min ski, 1 min run, 1 min row, 1 min run.'), ARRAY[
    'Dumbbell Squat          | 3 | 20 | 20 | 20, add weight once all reps are done',
    'Single Leg Glute Bridge | 3 | 12 | 12 | 12 each side',
    'Air Squat               | 3 | 8  | 12 | 8-12 close feet',
    'Dips                    | 3 | 12 | 12 | 12',
    'Deficit Push-Up         | 3 | 12 | 12 | 12',
    'Ski Erg                 | 5 | 60 | 60 | 1 min (EMOM)',
    'Run                     | 10 | 60 | 60 | 1 min (EMOM)',
    'Row Erg                 | 5 | 60 | 60 | 1 min (EMOM)']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a02', 7,
    'Team WOD: I Go, You Go', 'Team Conditioning', 50,
    'Four 10-minute I-go-you-go (or AMRAP) blocks with 2 min rest. 1) 1 wall walk (or 2 box walks), 10 shoulder taps each side (on the wall or box), 10 box jumps (or step-ups). 2) 5 devil press, 5 plank DB drags each side. 3) 10 hollow rocks, 10 plate sit-ups, 30 plank jacks on the elbows. 4) 10 dual-KB sumo deadlifts, 10 gorilla rows total, 10 KB swings.'), ARRAY[
    'Wall Walk                                | 4 | 1  | 2  | 1 wall walk or 2 box walks',
    'Shoulder Taps                            | 4 | 10 | 10 | 10 each side',
    'Box Jump                                 | 4 | 10 | 10 | 10, or step-ups',
    'Devil Press                              | 4 | 5  | 5  | 5',
    'Plank Pass-Through                       | 4 | 5  | 5  | 5 each side, slide the DB',
    'Hollow Rock                              | 4 | 10 | 10 | 10',
    'Weighted Sit Up (with dumbbell on chest) | 4 | 10 | 10 | 10 plate sit-ups',
    'Plank Jacks                              | 4 | 30 | 30 | 30 on the elbows',
    'Sumo Deadlift                            | 4 | 10 | 10 | 10 dual KB',
    'Gorilla Row                              | 4 | 10 | 10 | 10 total',
    'Kettlebell Swing                         | 4 | 10 | 10 | 10']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a02', 8,
    'Hinge & Shoulders: Heavy Deadlift & Carry', 'Strength + Conditioning', 60,
    'Warm-up: 3 rounds of 1 min machine, 10 inverted body rows, 10 light single-leg deadlifts each leg. Strength: 5 rounds of 4 deadlifts + 10 heavy Russian KB swings. Accessory: 3 rounds of 8 seated DB press each arm + 12 lateral raises. Finisher: 12-15 min AMRAP of 1 min run, 16 weighted step-ups, 4 lengths suitcase carry with two KBs.'), ARRAY[
    'Deadlift                       | 5 | 4  | 4  | 4',
    'Kettlebell Swing               | 5 | 10 | 10 | 10 heavy Russian',
    'Seated Dumbbell Shoulder Press | 3 | 8  | 8  | 8 each arm',
    'Dumbbell Lateral Raise         | 3 | 12 | 12 | 12',
    'Run                            | 4 | 60 | 60 | 1 min',
    'Dumbbell Step Up               | 4 | 16 | 16 | 16 weighted, total',
    'Suitcase Carry                 | 4 | 4  | 4  | 4 lengths, two KBs']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a02', 10,
    'Upper: Incline Bench & Chin-Ups', 'Strength + Conditioning', 60,
    'Warm-up: 1 min machine, 8 half-kneeling DB press each arm, 10 band face pulls. Strength: 4 rounds of 6 incline bench + max barbell upright rows, then 4 rounds of 6-8 bent-over rows from the floor + a max set of chin-ups. Finisher: 5 min AMRAP of a 3-6-9 Russian twist ladder (each side) with 5 cal row between rungs, then 5 min AMRAP of a 3-6-9 walking lunge ladder with 5 cal bike between rungs.'), ARRAY[
    'Incline Barbell Bench Press | 4 | 6  | 6  | 6',
    'Barbell Upright Row         | 4 | 10 | 15 | max reps',
    'Barbell Bent-Over Row       | 4 | 6  | 8  | 6-8 from the floor',
    'Chin Up                     | 4 | 6  | 12 | max set',
    'Russian Twist               | 4 | 3  | 12 | 3-6-9... ladder, each side',
    'Row Erg                     | 4 | 5  | 5  | 5 cal between rungs',
    'Walking Lunge               | 4 | 3  | 12 | 3-6-9... ladder, each side',
    'Assault Bike                | 4 | 5  | 5  | 5 cal between rungs']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a02', 12,
    'Lower: Heel-Raised Squat & Glutes', 'Strength + Conditioning', 50,
    'Warm-up: 3 rounds of 1 min machine, 10 narrow-stance squats, 10 glute bridges. Strength: 5 rounds of 10 narrow-stance heel-raised back squats + 10 box jumps. Accessory: 3 rounds of 10 hip thrusts + 12 biceps curls. Finisher: 5 rounds of 30 s on / 30 s off ski erg sprints.'), ARRAY[
    'Back Squat           | 5 | 10 | 10 | 10 narrow feet, heels raised',
    'Box Jump             | 5 | 10 | 10 | 10',
    'Hip Thrust           | 3 | 10 | 10 | 10',
    'Dumbbell Bicep Curl  | 3 | 12 | 12 | 12',
    'Ski Erg              | 5 | 30 | 30 | 30 sec sprint, 30 sec off']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a02', 14,
    'Team WOD: 2-to-10 Ladders', 'Team Conditioning', 50,
    'Two ladders of 2-4-6-8-10-10-8-6-4-2: only the first movement climbs, the other two stay fixed (2, 10, 50, then 4, 10, 50...). Finish one ladder before starting the next. 1) T2B or plate V-ups, 10 jumping lunges each leg, 50 jump ropes. 2) Pull-ups (at home: TRX or under-a-table rows), 10 dual-KB front-rack squats, 50 plank jacks on the hands (30 if 50 is too many).'), ARRAY[
    'Toes-to-Bar                   | 10 | 2  | 10 | 2-4-6-8-10-10-8-6-4-2, or plate V-ups',
    'Jumping Lunges                | 10 | 10 | 10 | 10 each leg',
    'Jump Rope                     | 10 | 50 | 50 | 50',
    'Pull-Up                       | 10 | 2  | 10 | 2-4-6-8-10-10-8-6-4-2, or TRX rows',
    'Double Kettlebell Front Squat | 10 | 10 | 10 | 10 front rack',
    'Plank Jacks                   | 10 | 30 | 50 | 50 on the hands (30 if too many)']);

-- ---- Block III ------------------------------------------------------------
SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a03', 1,
    'Hinge & Shoulders: Deadlift & Row', 'Strength + Conditioning', 55,
    'Warm-up: 3 rounds of 1 min machine, 10 dual-DB sumo deadlifts, 10 dual-DB high pulls. Strength: 4 rounds of 5 deadlifts + 12 cal row. Accessory: 3 rounds of 12 seated alternating DB press each arm + 15 lateral raises. Finisher: 12 min of 60 s jump rope or run, 20 American swings, 20 hollow rocks.'), ARRAY[
    'Deadlift                       | 4 | 5  | 5  | 5',
    'Row Erg                        | 4 | 12 | 12 | 12 cal',
    'Seated Dumbbell Shoulder Press | 3 | 12 | 12 | 12 alternating, each arm',
    'Dumbbell Lateral Raise         | 3 | 15 | 15 | 15',
    'Jump Rope                      | 4 | 60 | 60 | 60 sec, or run',
    'Kettlebell Swing               | 4 | 20 | 20 | 20 American',
    'Hollow Rock                    | 4 | 20 | 20 | 20']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a03', 3,
    'Upper: Close-Grip Bench & Pull-Ups', 'Strength + Conditioning', 60,
    'Warm-up: 1 min ski or row, 10 one-arm DB press, 10 TRX face pulls. Strength: 4 working sets of 8 narrow-grip bench press + 12 box step-overs. Accessory: 3 rounds of max low-bar pull-ups (6 minimum) + 12 dual-DB bent-over rows. Finisher: 2 x 5 min AMRAP of 5 burpee box jump-overs, 10 hanging leg or knee raises, 15 bodyweight squats.'), ARRAY[
    'Close-Grip Bench Press | 4 | 8  | 8  | 8',
    'Dumbbell Step Up       | 4 | 12 | 12 | 12 box step-overs, total',
    'Inverted Row           | 3 | 6  | 12 | max low-bar pull-ups, 6 minimum',
    'Dumbbell Bent Over Row | 3 | 12 | 12 | 12 both DBs',
    'Burpees                | 4 | 5  | 5  | 5 burpee box jump-overs',
    'Hanging Leg Raise      | 4 | 10 | 10 | 10 leg or knee raises',
    'Bodyweight Squat       | 4 | 15 | 15 | 15']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a03', 5,
    'Lower: Back Squat & Box Jumps', 'Strength + Conditioning', 55,
    'Warm-up: 10 lengths run, 10 inchworm push-ups, 1 length walking lunges. Strength: 4 rounds of 4-6 back squats + 12 box jumps. Accessory: 3 rounds of 8 split-stance hip thrusts each leg + 12-15 KB front press. Finisher: 10 min EMOM rotating wall walk (or box walk / inchworm), row, hand-release push-ups.'), ARRAY[
    'Back Squat           | 4 | 4  | 6  | 4-6',
    'Box Jump             | 4 | 12 | 12 | 12',
    'Hip Thrust           | 3 | 8  | 8  | 8 split stance, each leg',
    'Kettlebell Press     | 3 | 12 | 15 | 12-15 in front',
    'Wall Walk            | 3 | 1  | 3  | max in 1 min (EMOM), or box walk / inchworm',
    'Row Erg              | 3 | 60 | 60 | 1 min (EMOM)',
    'Hand-Release Push-Up | 3 | 10 | 15 | max in 1 min (EMOM)']);

SELECT pg_temp.exercises(pg_temp.day('a1f0c3e2-7b4d-4c1a-9e55-0c2d7b1e6a03', 7,
    'Team WOD: 90/30 Intervals', 'Team Conditioning', 50,
    'Three blocks of 90 s on / 30 s off, descending 21-18-15-12-9-6. Do the reps of the first movement, then max reps of the second until the 90 s are up. 1) Deadlifts (heavy, but not a 5-rep weight) + max wall balls. 2) Gorilla rows each side + max reverse-plank leg raises (knee raises to scale). 3) Dual-DB squats + max burpee dual-DB step-ups.'), ARRAY[
    'Deadlift          | 6 | 6  | 21 | 21-18-15-12-9-6, heavy',
    'Wall Balls        | 6 | 10 | 20 | max to the end of 90 sec',
    'Gorilla Row       | 6 | 6  | 21 | 21-18-15-12-9-6 each side',
    'Lying Leg Raise   | 6 | 10 | 20 | max reverse-plank leg raises (or knee raises)',
    'Dumbbell Squat    | 6 | 6  | 21 | 21-18-15-12-9-6, dual DB',
    'Dumbbell Step Up  | 6 | 5  | 15 | max burpee + dual-DB step-ups']);
