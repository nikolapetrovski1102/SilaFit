-- App-facing CRUD for a user's own diet plan, mirroring UserSplits.sql's
-- shape (same Outcome/EntityId/Detail result, same validation ranges) for
-- the meal-planning equivalent. Ownership is a direct
-- nutritionplans.owneruserid = p_userid match, checked inside the same
-- transaction as the write. No AdminAuditLog rows - see UserSplits.sql.

CREATE OR REPLACE FUNCTION dbo.usp_userdietplans_getowned(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT dp.dietplanid,
           dp.name,
           dp.description,
           dp.heroimageurl,
           dp.periodtype,
           dp.durationdays,
           dp.issystemdefault,
           dp.sortorder,
           dp.visibility,
           dp.owneruserid,
           dp.isaigenerated,
           dp.aikeptatutc
    FROM dbo.nutritionplans dp
    WHERE dp.owneruserid = p_userid
    ORDER BY dp.sortorder, dp.name;
    RETURN NEXT c1;
END $$;

-- p_isaigenerated is only ever passed true by Silen.Tools.WeeklyPlanGeneration;
-- see the matching comment on usp_usersplit_upsert (UserSplits.sql) - same
-- rationale, left untouched on UPDATE.
CREATE OR REPLACE FUNCTION dbo.usp_userdietplan_upsert(
    p_dietplanid uuid DEFAULT NULL,
    p_userid uuid DEFAULT NULL,
    p_name text DEFAULT NULL,
    p_description text DEFAULT NULL,
    p_heroimageurl text DEFAULT NULL,
    p_periodtype text DEFAULT 'Weekly',
    p_durationdays smallint DEFAULT 7,
    p_isaigenerated boolean DEFAULT false
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_dietplanid uuid := p_dietplanid;
    v_name text := btrim(p_name);
    v_description text := NULLIF(btrim(p_description), '');
    v_heroimageurl text := NULLIF(btrim(p_heroimageurl), '');
    v_periodtype text := btrim(p_periodtype);
BEGIN
    IF v_name IS NULL OR v_name = '' THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A plan name is required.');
        RETURN;
    END IF;

    IF v_periodtype IS NULL OR v_periodtype COLLATE ci NOT IN ('Weekly', 'Monthly') THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'Period type must be Weekly or Monthly.');
        RETURN;
    END IF;

    IF p_durationdays < 1 OR p_durationdays > 31 THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A plan lasts between 1 and 31 days.');
        RETURN;
    END IF;

    IF v_dietplanid IS NULL THEN
        v_dietplanid := gen_random_uuid();

        -- Always Private on create, same rationale as usp_usersplit_upsert:
        -- this is the user's own content, not something to publish.
        INSERT INTO dbo.nutritionplans
            (dietplanid, name, description, heroimageurl, periodtype, durationdays,
             issystemdefault, sortorder, visibility, owneruserid, isaigenerated)
        VALUES
            (v_dietplanid, v_name, v_description, v_heroimageurl, v_periodtype, p_durationdays,
             false, 0, 'Private', p_userid, p_isaigenerated);
    ELSE
        IF NOT EXISTS (SELECT 1 FROM dbo.nutritionplans WHERE dietplanid = v_dietplanid) THEN
            RETURN NEXT dbo.outcome_cursor(1, v_dietplanid, 'That plan no longer exists.');
            RETURN;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM dbo.nutritionplans WHERE dietplanid = v_dietplanid AND owneruserid = p_userid) THEN
            RETURN NEXT dbo.outcome_cursor(2, v_dietplanid, 'You can only edit plans you built yourself.');
            RETURN;
        END IF;

        UPDATE dbo.nutritionplans
        SET name = v_name,
            description = v_description,
            heroimageurl = v_heroimageurl,
            periodtype = v_periodtype,
            durationdays = p_durationdays
        WHERE dietplanid = v_dietplanid;
    END IF;

    RETURN NEXT dbo.outcome_cursor(0, v_dietplanid, NULL);
END $$;

-- Blocked outright while any user has the plan active, same guard as
-- usp_usersplit_delete.
CREATE OR REPLACE FUNCTION dbo.usp_userdietplan_delete(
    p_dietplanid uuid,
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_name text;
BEGIN
    SELECT name INTO v_name FROM dbo.nutritionplans WHERE dietplanid = p_dietplanid;

    IF v_name IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_dietplanid, 'That plan no longer exists.');
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM dbo.nutritionplans WHERE dietplanid = p_dietplanid AND owneruserid = p_userid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_dietplanid, 'You can only delete plans you built yourself.');
        RETURN;
    END IF;

    IF EXISTS (SELECT 1 FROM dbo.useractivedietplans WHERE dietplanid = p_dietplanid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_dietplanid,
            '''' || v_name || ''' is your active plan - switch to another plan before deleting it.');
        RETURN;
    END IF;

    DELETE FROM dbo.dietplanmeals
    WHERE dietplandayid IN (SELECT dietplandayid FROM dbo.dietplandays WHERE dietplanid = p_dietplanid);

    DELETE FROM dbo.dietplandays WHERE dietplanid = p_dietplanid;
    DELETE FROM dbo.nutritionplans WHERE dietplanid = p_dietplanid;

    -- Built-from-ingredients meals no plan slot points at any more.
    DELETE FROM dbo.mealsuggestions ms
    WHERE ms.owneruserid = p_userid
      AND NOT EXISTS (SELECT 1 FROM dbo.dietplanmeals m WHERE m.mealsuggestionid = ms.mealsuggestionid);

    RETURN NEXT dbo.outcome_cursor(0, p_dietplanid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_userdietplanday_upsert(
    p_dietplandayid uuid DEFAULT NULL,
    p_dietplanid uuid DEFAULT NULL,
    p_userid uuid DEFAULT NULL,
    p_dayindex smallint DEFAULT NULL,
    p_title text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_dietplandayid uuid := p_dietplandayid;
    v_title text := NULLIF(btrim(p_title), '');
    v_planname text;
BEGIN
    SELECT name INTO v_planname FROM dbo.nutritionplans WHERE dietplanid = p_dietplanid;

    IF v_planname IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_dietplanid, 'That plan no longer exists.');
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM dbo.nutritionplans WHERE dietplanid = p_dietplanid AND owneruserid = p_userid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_dietplanid, 'You can only edit plans you built yourself.');
        RETURN;
    END IF;

    IF p_dayindex < 1 OR p_dayindex > 31 THEN
        RETURN NEXT dbo.outcome_cursor(3, p_dietplanid, 'Day index must be between 1 and 31.');
        RETURN;
    END IF;

    IF EXISTS (SELECT 1
               FROM dbo.dietplandays
               WHERE dietplanid = p_dietplanid
                 AND dayindex = p_dayindex
                 AND (v_dietplandayid IS NULL OR dietplandayid <> v_dietplandayid)) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_dietplanid,
            'Day ' || p_dayindex::text || ' already exists in ''' || v_planname || '''.');
        RETURN;
    END IF;

    IF v_dietplandayid IS NULL THEN
        v_dietplandayid := gen_random_uuid();

        INSERT INTO dbo.dietplandays (dietplandayid, dietplanid, dayindex, title)
        VALUES (v_dietplandayid, p_dietplanid, p_dayindex, v_title);
    ELSE
        UPDATE dbo.dietplandays
        SET dayindex = p_dayindex,
            title = v_title
        WHERE dietplandayid = v_dietplandayid
          AND dietplanid = p_dietplanid;

        IF NOT FOUND THEN
            RETURN NEXT dbo.outcome_cursor(1, v_dietplandayid, 'That day no longer exists on this plan.');
            RETURN;
        END IF;
    END IF;

    RETURN NEXT dbo.outcome_cursor(0, v_dietplandayid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_userdietplanday_delete(
    p_dietplandayid uuid,
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1
                   FROM dbo.dietplandays d
                   INNER JOIN dbo.nutritionplans p ON p.dietplanid = d.dietplanid
                   WHERE d.dietplandayid = p_dietplandayid) THEN
        RETURN NEXT dbo.outcome_cursor(1, p_dietplandayid, 'That day no longer exists.');
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM dbo.dietplandays d
                   INNER JOIN dbo.nutritionplans p ON p.dietplanid = d.dietplanid
                   WHERE d.dietplandayid = p_dietplandayid
                     AND p.owneruserid = p_userid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_dietplandayid, 'You can only edit plans you built yourself.');
        RETURN;
    END IF;

    DELETE FROM dbo.dietplanmeals WHERE dietplandayid = p_dietplandayid;
    DELETE FROM dbo.dietplandays WHERE dietplandayid = p_dietplandayid;

    -- Built-from-ingredients meals no plan slot points at any more.
    DELETE FROM dbo.mealsuggestions ms
    WHERE ms.owneruserid = p_userid
      AND NOT EXISTS (SELECT 1 FROM dbo.dietplanmeals m WHERE m.mealsuggestionid = ms.mealsuggestionid);

    RETURN NEXT dbo.outcome_cursor(0, p_dietplandayid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_userdietplanmeal_upsert(
    p_dietplanmealid uuid DEFAULT NULL,
    p_dietplandayid uuid DEFAULT NULL,
    p_userid uuid DEFAULT NULL,
    p_mealtype text DEFAULT NULL,
    p_mealsuggestionid uuid DEFAULT NULL,
    p_sortorder integer DEFAULT 0
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_dietplanmealid uuid := p_dietplanmealid;
    v_mealtype text := btrim(p_mealtype);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.dietplandays WHERE dietplandayid = p_dietplandayid) THEN
        RETURN NEXT dbo.outcome_cursor(1, p_dietplandayid, 'That plan day no longer exists.');
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM dbo.dietplandays d
                   INNER JOIN dbo.nutritionplans p ON p.dietplanid = d.dietplanid
                   WHERE d.dietplandayid = p_dietplandayid
                     AND p.owneruserid = p_userid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_dietplandayid, 'You can only edit plans you built yourself.');
        RETURN;
    END IF;

    IF v_mealtype IS NULL OR v_mealtype COLLATE ci NOT IN ('Breakfast', 'Lunch', 'Dinner', 'Snack') THEN
        RETURN NEXT dbo.outcome_cursor(3, p_dietplandayid, 'Meal type must be Breakfast, Lunch, Dinner or Snack.');
        RETURN;
    END IF;

    -- The shared catalog, or a meal this user built from ingredients.
    IF NOT EXISTS (SELECT 1
                   FROM dbo.mealsuggestions
                   WHERE mealsuggestionid = p_mealsuggestionid
                     AND (owneruserid IS NULL OR owneruserid = p_userid)) THEN
        RETURN NEXT dbo.outcome_cursor(1, p_mealsuggestionid, 'That meal suggestion no longer exists.');
        RETURN;
    END IF;

    IF v_dietplanmealid IS NULL THEN
        v_dietplanmealid := gen_random_uuid();

        INSERT INTO dbo.dietplanmeals (dietplanmealid, dietplandayid, mealtype, mealsuggestionid, sortorder)
        VALUES (v_dietplanmealid, p_dietplandayid, v_mealtype, p_mealsuggestionid, p_sortorder);
    ELSE
        UPDATE dbo.dietplanmeals
        SET mealtype = v_mealtype,
            mealsuggestionid = p_mealsuggestionid,
            sortorder = p_sortorder
        WHERE dietplanmealid = v_dietplanmealid
          AND dietplandayid = p_dietplandayid;

        IF NOT FOUND THEN
            RETURN NEXT dbo.outcome_cursor(1, v_dietplanmealid, 'That meal slot no longer exists on this day.');
            RETURN;
        END IF;
    END IF;

    RETURN NEXT dbo.outcome_cursor(0, v_dietplanmealid, NULL);
END $$;

-- A meal the user builds from ingredients in the diet-plan wizard: a private
-- mealsuggestions row whose macros are summed from dbo.foodnutrition (per
-- 100 g) for the chosen grams, one "150 g Chicken breast" ingredient line per
-- food (the shape IngredientSummaryFormatter aggregates into the shopping
-- list), and the day's slot pointing at it - all in one transaction.
-- p_itemsjson: [{ "foodNutritionId": 123, "grams": 150 }, ...]. Only shared
-- catalog foods and the caller's own count; others are ignored.
CREATE OR REPLACE FUNCTION dbo.usp_userdietplancustommeal_create(
    p_dietplandayid uuid,
    p_userid uuid,
    p_mealtype text,
    p_title text,
    p_sortorder integer DEFAULT 0,
    p_itemsjson text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_mealtype text := btrim(p_mealtype);
    v_title text := btrim(p_title);
    v_items jsonb;
    v_mealsuggestionid uuid := gen_random_uuid();
    v_dietplanmealid uuid := gen_random_uuid();
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.dietplandays WHERE dietplandayid = p_dietplandayid) THEN
        RETURN NEXT dbo.outcome_cursor(1, p_dietplandayid, 'That plan day no longer exists.');
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM dbo.dietplandays d
                   INNER JOIN dbo.nutritionplans p ON p.dietplanid = d.dietplanid
                   WHERE d.dietplandayid = p_dietplandayid
                     AND p.owneruserid = p_userid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_dietplandayid, 'You can only edit plans you built yourself.');
        RETURN;
    END IF;

    IF v_mealtype IS NULL OR v_mealtype COLLATE ci NOT IN ('Breakfast', 'Lunch', 'Dinner', 'Snack') THEN
        RETURN NEXT dbo.outcome_cursor(3, p_dietplandayid, 'Meal type must be Breakfast, Lunch, Dinner or Snack.');
        RETURN;
    END IF;

    IF v_title IS NULL OR v_title = '' THEN
        RETURN NEXT dbo.outcome_cursor(3, p_dietplandayid, 'Give the meal a name.');
        RETURN;
    END IF;

    -- Resolved once into a JSON array of {ordinal,name,grams,calories,...} so the
    -- three inserts below read the same rows.
    IF p_itemsjson IS NOT NULL AND p_itemsjson IS JSON ARRAY THEN
        SELECT jsonb_agg(jsonb_build_object(
                   'ordinal', j.ordinal,
                   'name', f.name,
                   'grams', i.grams,
                   'calories', COALESCE(f.calorieskcal, 0) * i.grams / 100,
                   'protein', COALESCE(f.proteing, 0) * i.grams / 100,
                   'carbs', COALESCE(f.carbohydrateg, 0) * i.grams / 100,
                   'fats', COALESCE(f.fatg, 0) * i.grams / 100))
        INTO v_items
        FROM jsonb_array_elements(p_itemsjson::jsonb) WITH ORDINALITY AS j(value, ordinal)
        CROSS JOIN LATERAL (
            SELECT CASE WHEN jsonb_typeof(j.value) = 'object' THEN (j.value ->> 'foodNutritionId')::bigint END AS foodnutritionid,
                   CASE WHEN jsonb_typeof(j.value) = 'object' THEN (j.value ->> 'grams')::numeric(9,1) END AS grams
        ) i
        INNER JOIN dbo.foodnutrition f ON f.foodnutritionid = i.foodnutritionid
        WHERE i.grams > 0 AND i.grams <= 5000
          AND (f.createdbyuserid IS NULL OR f.createdbyuserid = p_userid);
    END IF;

    IF v_items IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(3, p_dietplandayid, 'Add at least one ingredient.');
        RETURN;
    END IF;

    INSERT INTO dbo.mealsuggestions
        (mealsuggestionid, title, mealtype, calorieskcal, proteing, carbsg, fatsg,
         suggestedmonth, issystemdefault, sortorder, owneruserid)
    SELECT v_mealsuggestionid, v_title, v_mealtype,
           round(SUM(it.calories), 0)::smallint,
           round(SUM(it.protein), 0)::smallint,
           round(SUM(it.carbs), 0)::smallint,
           round(SUM(it.fats), 0)::smallint,
           NULL, false, 0, p_userid
    FROM jsonb_to_recordset(v_items) AS it(calories numeric, protein numeric, carbs numeric, fats numeric);

    INSERT INTO dbo.mealsuggestioningredients (mealsuggestionid, sortorder, ingredienttext)
    SELECT v_mealsuggestionid,
           (ROW_NUMBER() OVER (ORDER BY it.ordinal) - 1)::smallint,
           left(round(it.grams, 0)::int::text || ' g ' || it.name, 1000)
    FROM jsonb_to_recordset(v_items) AS it(ordinal bigint, name text, grams numeric);

    INSERT INTO dbo.dietplanmeals (dietplanmealid, dietplandayid, mealtype, mealsuggestionid, sortorder)
    VALUES (v_dietplanmealid, p_dietplandayid, v_mealtype, v_mealsuggestionid, p_sortorder);

    RETURN NEXT dbo.outcome_cursor(0, v_dietplanmealid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_userdietplanmeal_delete(
    p_dietplanmealid uuid,
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.dietplanmeals WHERE dietplanmealid = p_dietplanmealid) THEN
        RETURN NEXT dbo.outcome_cursor(1, p_dietplanmealid, 'That meal slot no longer exists.');
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM dbo.dietplanmeals m
                   INNER JOIN dbo.dietplandays d ON d.dietplandayid = m.dietplandayid
                   INNER JOIN dbo.nutritionplans p ON p.dietplanid = d.dietplanid
                   WHERE m.dietplanmealid = p_dietplanmealid
                     AND p.owneruserid = p_userid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_dietplanmealid, 'You can only edit plans you built yourself.');
        RETURN;
    END IF;

    DELETE FROM dbo.dietplanmeals WHERE dietplanmealid = p_dietplanmealid;

    -- Built-from-ingredients meals no plan slot points at any more.
    DELETE FROM dbo.mealsuggestions ms
    WHERE ms.owneruserid = p_userid
      AND NOT EXISTS (SELECT 1 FROM dbo.dietplanmeals m WHERE m.mealsuggestionid = ms.mealsuggestionid);

    RETURN NEXT dbo.outcome_cursor(0, p_dietplanmealid, NULL);
END $$;

-- Marks an AI-generated plan as permanent, diet-plan counterpart of
-- usp_usersplit_keep (see UserSplits.sql for the full rationale).
CREATE OR REPLACE FUNCTION dbo.usp_userdietplan_keep(
    p_dietplanid uuid,
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.nutritionplans WHERE dietplanid = p_dietplanid) THEN
        RETURN NEXT dbo.outcome_cursor(1, p_dietplanid, 'That plan no longer exists.');
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM dbo.nutritionplans WHERE dietplanid = p_dietplanid AND owneruserid = p_userid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_dietplanid, 'You can only keep plans you built yourself.');
        RETURN;
    END IF;

    UPDATE dbo.nutritionplans
    SET aikeptatutc = dbo.sysutcdatetime()
    WHERE dietplanid = p_dietplanid
      AND isaigenerated
      AND aikeptatutc IS NULL;

    RETURN NEXT dbo.outcome_cursor(0, p_dietplanid, NULL);
END $$;

-- Sets a user's current diet plan, mirroring dbo.usp_useractivesplit_set
-- (see Splits.sql). Written by the app's activate endpoint and, for on-demand
-- AI generation only, by Silen.Services. useractivedietplans is still just a
-- label: it does not pre-populate meallogs; the Nutrition screen reads it
-- through usp_useractivedietplan_get and renders the plan's meals for the
-- viewed day.
CREATE OR REPLACE FUNCTION dbo.usp_useractivedietplan_set(
    p_userid uuid,
    p_dietplanid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO dbo.useractivedietplans (userid, dietplanid, activatedatutc)
    VALUES (p_userid, p_dietplanid, dbo.sysutcdatetime())
    ON CONFLICT (userid) DO UPDATE
    SET dietplanid = EXCLUDED.dietplanid, activatedatutc = EXCLUDED.activatedatutc;
END $$;

-- The caller's current diet plan header, or no row when none is active. The
-- app then loads the plan's days/meals through usp_dietplans_getdetail, so this
-- stays a single-row lookup rather than duplicating the detail result sets.
CREATE OR REPLACE FUNCTION dbo.usp_useractivedietplan_get(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT a.userid, a.dietplanid, a.activatedatutc, p.name, p.durationdays
    FROM dbo.useractivedietplans a
    INNER JOIN dbo.nutritionplans p ON p.dietplanid = a.dietplanid
    WHERE a.userid = p_userid;
    RETURN NEXT c1;
END $$;
