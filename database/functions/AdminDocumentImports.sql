-- AI document imports: a trainer's uploaded PDF/Word program, read by the model
-- in the API (TrainerDocumentService), lands here as one JSON payload and becomes
-- a complete split or diet plan in a single transaction - the program row, every
-- day and every exercise/meal - so a half-imported program can never be left
-- behind. The new program is Private and owned by the trainer; they review it in
-- the console and assign it like any other.

-- p_daysjson: [{ "dayIndex", "title", "focusLabel", "estimatedMinutes", "isRestDay",
--   "exercises": [{ "exerciseId" (null = new), "name", "muscleGroup", "sets",
--                   "repsLow", "repsHigh", "notes" }] }]
-- An exercise the library doesn't have yet is added to it (same as the console's
-- "New exercise"), matched by name first so two days naming it share one row.
CREATE OR REPLACE FUNCTION dbo.usp_admin_split_importgenerated(
    p_name text,
    p_level text,
    p_description text,
    p_durationdays smallint,
    p_daysjson jsonb,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_splitid uuid := gen_random_uuid();
    v_name text := left(NULLIF(btrim(p_name), ''), 150);
    v_level text := COALESCE(NULLIF(btrim(p_level), ''), 'Intermediate');
    v_day jsonb;
    v_exercise jsonb;
    v_splitdayid uuid;
    v_exerciseid uuid;
    v_sort smallint;
    v_daycount integer := 0;
    v_exercisecount integer := 0;
    v_newexercisecount integer := 0;
    v_musclegroup text;
    v_replow smallint;
    v_rephigh smallint;
BEGIN
    IF v_name IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A split name is required.');
        RETURN;
    END IF;

    IF p_durationdays < 1 OR p_durationdays > 182 THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A split lasts between 1 and 182 days (26 weeks).');
        RETURN;
    END IF;

    IF v_level COLLATE ci NOT IN ('Beginner', 'Intermediate', 'Advanced') THEN
        v_level := 'Intermediate';
    END IF;

    INSERT INTO dbo.workoutsplits
        (splitid, name, category, level, durationdays, description, issystemdefault, sortorder,
         visibility, owneradminuserid)
    VALUES
        (v_splitid, v_name, 'Custom', v_level, p_durationdays, left(NULLIF(btrim(p_description), ''), 500),
         false, 0, 'Private', p_actoradminuserid);

    FOR v_day IN SELECT value FROM jsonb_array_elements(COALESCE(p_daysjson, '[]'::jsonb))
    LOOP
        CONTINUE WHEN jsonb_typeof(v_day->'dayIndex') IS DISTINCT FROM 'number';

        IF (v_day->>'dayIndex')::int < 1 OR (v_day->>'dayIndex')::int > p_durationdays THEN
            CONTINUE;
        END IF;

        IF EXISTS (SELECT 1 FROM dbo.splitdays WHERE splitid = v_splitid
                   AND dayindex = (v_day->>'dayIndex')::smallint) THEN
            CONTINUE;
        END IF;

        v_splitdayid := gen_random_uuid();
        INSERT INTO dbo.splitdays (splitdayid, splitid, dayindex, title, focuslabel, estimatedminutes, isrestday)
        VALUES (v_splitdayid, v_splitid, (v_day->>'dayIndex')::smallint,
                left(COALESCE(NULLIF(btrim(v_day->>'title'), ''), 'Day ' || (v_day->>'dayIndex')), 150),
                left(NULLIF(btrim(v_day->>'focusLabel'), ''), 100),
                LEAST(GREATEST(COALESCE((v_day->>'estimatedMinutes')::int, 45), 5), 240)::smallint,
                COALESCE((v_day->>'isRestDay')::boolean, false));
        v_daycount := v_daycount + 1;

        v_sort := 0;
        FOR v_exercise IN SELECT value FROM jsonb_array_elements(COALESCE(v_day->'exercises', '[]'::jsonb))
        LOOP
            v_exerciseid := NULL;
            IF NULLIF(v_exercise->>'exerciseId', '') IS NOT NULL THEN
                SELECT exerciseid INTO v_exerciseid FROM dbo.exercises
                WHERE exerciseid = (v_exercise->>'exerciseId')::uuid;
            END IF;

            IF v_exerciseid IS NULL AND NULLIF(btrim(v_exercise->>'name'), '') IS NOT NULL THEN
                SELECT exerciseid INTO v_exerciseid FROM dbo.exercises
                WHERE name = btrim(v_exercise->>'name')
                  AND createdbyuserid IS NULL
                ORDER BY createdatutc
                LIMIT 1;

                IF v_exerciseid IS NULL THEN
                    v_musclegroup := lower(COALESCE(v_exercise->>'muscleGroup', ''));
                    IF v_musclegroup NOT IN ('chest', 'back', 'legs', 'shoulders', 'arms', 'core') THEN
                        v_musclegroup := 'core';
                    END IF;
                    v_exerciseid := gen_random_uuid();
                    INSERT INTO dbo.exercises (exerciseid, name, musclegroup)
                    VALUES (v_exerciseid, left(btrim(v_exercise->>'name'), 150), v_musclegroup);
                    v_newexercisecount := v_newexercisecount + 1;
                END IF;
            END IF;

            CONTINUE WHEN v_exerciseid IS NULL;

            v_replow := LEAST(GREATEST(COALESCE((v_exercise->>'repsLow')::int, 8), 1), 100)::smallint;
            v_rephigh := LEAST(GREATEST(COALESCE((v_exercise->>'repsHigh')::int, v_replow), v_replow), 100)::smallint;
            v_sort := v_sort + 1;

            INSERT INTO dbo.splitdayexercises
                (splitdayid, exerciseid, sortorder, targetsets, targetrepslow, targetrepshigh, sourcereps)
            VALUES
                (v_splitdayid, v_exerciseid, v_sort,
                 LEAST(GREATEST(COALESCE((v_exercise->>'sets')::int, 3), 1), 20)::smallint,
                 v_replow, v_rephigh, left(NULLIF(btrim(v_exercise->>'notes'), ''), 300));
            v_exercisecount := v_exercisecount + 1;
        END LOOP;
    END LOOP;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Create', 'WorkoutSplit', v_splitid::text,
            'Imported split ''' || v_name || ''' from a document (' || p_durationdays::text || ' days, '
            || v_daycount::text || ' day(s), ' || v_exercisecount::text || ' exercise row(s), '
            || v_newexercisecount::text || ' new exercise(s))', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_splitid, NULL);
END $$;

-- p_daysjson: [{ "dayIndex", "title", "meals": [{ "mealType", "title", "description",
--   "calories", "protein", "carbs", "fats", "ingredients": [text], "steps": [text] }] }]
-- Every meal becomes a meal suggestion owned by the trainer (owneradminuserid):
-- it carries the document's own recipe, stays out of the public catalog, and is
-- what the plan's meal slots point at.
CREATE OR REPLACE FUNCTION dbo.usp_admin_dietplan_importgenerated(
    p_name text,
    p_description text,
    p_durationdays smallint,
    p_daysjson jsonb,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_dietplanid uuid := gen_random_uuid();
    v_name text := left(NULLIF(btrim(p_name), ''), 200);
    v_day jsonb;
    v_meal jsonb;
    v_dietplandayid uuid;
    v_mealsuggestionid uuid;
    v_mealtype text;
    v_sort integer;
    v_daycount integer := 0;
    v_mealcount integer := 0;
BEGIN
    IF v_name IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A plan name is required.');
        RETURN;
    END IF;

    IF p_durationdays < 1 OR p_durationdays > 182 THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A plan lasts between 1 and 182 days (26 weeks).');
        RETURN;
    END IF;

    INSERT INTO dbo.nutritionplans
        (dietplanid, name, description, periodtype, durationdays, issystemdefault, sortorder,
         visibility, owneradminuserid)
    VALUES
        (v_dietplanid, v_name, left(NULLIF(btrim(p_description), ''), 1000),
         CASE WHEN p_durationdays <= 7 THEN 'Weekly' ELSE 'Monthly' END, p_durationdays, false, 0,
         'Private', p_actoradminuserid);

    FOR v_day IN SELECT value FROM jsonb_array_elements(COALESCE(p_daysjson, '[]'::jsonb))
    LOOP
        CONTINUE WHEN jsonb_typeof(v_day->'dayIndex') IS DISTINCT FROM 'number';

        IF (v_day->>'dayIndex')::int < 1 OR (v_day->>'dayIndex')::int > p_durationdays THEN
            CONTINUE;
        END IF;

        IF EXISTS (SELECT 1 FROM dbo.dietplandays WHERE dietplanid = v_dietplanid
                   AND dayindex = (v_day->>'dayIndex')::smallint) THEN
            CONTINUE;
        END IF;

        v_dietplandayid := gen_random_uuid();
        INSERT INTO dbo.dietplandays (dietplandayid, dietplanid, dayindex, title)
        VALUES (v_dietplandayid, v_dietplanid, (v_day->>'dayIndex')::smallint,
                left(NULLIF(btrim(v_day->>'title'), ''), 200));
        v_daycount := v_daycount + 1;

        v_sort := 0;
        FOR v_meal IN SELECT value FROM jsonb_array_elements(COALESCE(v_day->'meals', '[]'::jsonb))
        LOOP
            CONTINUE WHEN NULLIF(btrim(v_meal->>'title'), '') IS NULL;

            v_mealtype := initcap(lower(COALESCE(v_meal->>'mealType', 'Snack')));
            IF v_mealtype NOT IN ('Breakfast', 'Lunch', 'Dinner', 'Snack') THEN
                v_mealtype := 'Snack';
            END IF;

            v_mealsuggestionid := gen_random_uuid();
            INSERT INTO dbo.mealsuggestions
                (mealsuggestionid, title, mealtype, description, calorieskcal, proteing, carbsg, fatsg,
                 issystemdefault, sortorder, owneradminuserid)
            VALUES
                (v_mealsuggestionid, left(btrim(v_meal->>'title'), 200), v_mealtype,
                 left(NULLIF(btrim(v_meal->>'description'), ''), 500),
                 LEAST(GREATEST(COALESCE((v_meal->>'calories')::int, 0), 0), 5000)::smallint,
                 LEAST(GREATEST(COALESCE((v_meal->>'protein')::int, 0), 0), 1000)::smallint,
                 LEAST(GREATEST(COALESCE((v_meal->>'carbs')::int, 0), 0), 1000)::smallint,
                 LEAST(GREATEST(COALESCE((v_meal->>'fats')::int, 0), 0), 1000)::smallint,
                 false, 0, p_actoradminuserid);

            INSERT INTO dbo.mealsuggestioningredients (mealsuggestionid, sortorder, ingredienttext)
            SELECT v_mealsuggestionid, (row_number() OVER (ORDER BY x.ord))::smallint, left(btrim(x.line), 1000)
            FROM jsonb_array_elements_text(COALESCE(v_meal->'ingredients', '[]'::jsonb)) WITH ORDINALITY AS x(line, ord)
            WHERE NULLIF(btrim(x.line), '') IS NOT NULL;

            INSERT INTO dbo.mealsuggestioninstructions (mealsuggestionid, sortorder, instructiontext)
            SELECT v_mealsuggestionid, (row_number() OVER (ORDER BY x.ord))::smallint, left(btrim(x.line), 2000)
            FROM jsonb_array_elements_text(COALESCE(v_meal->'steps', '[]'::jsonb)) WITH ORDINALITY AS x(line, ord)
            WHERE NULLIF(btrim(x.line), '') IS NOT NULL;

            v_sort := v_sort + 1;
            INSERT INTO dbo.dietplanmeals (dietplandayid, mealtype, mealsuggestionid, sortorder)
            VALUES (v_dietplandayid, v_mealtype, v_mealsuggestionid, v_sort);
            v_mealcount := v_mealcount + 1;
        END LOOP;
    END LOOP;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Create', 'DietPlan', v_dietplanid::text,
            'Imported diet plan ''' || v_name || ''' from a document (' || p_durationdays::text || ' days, '
            || v_daycount::text || ' day(s), ' || v_mealcount::text || ' meal(s))', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_dietplanid, NULL);
END $$;
