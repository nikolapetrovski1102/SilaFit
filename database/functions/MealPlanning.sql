-- TargetCalories/TargetProteinG/TargetCarbsG/TargetFatsG are AES-256-GCM
-- ciphertext (Silen.Common.Helpers.FieldCipher), encrypted/decrypted at the
-- MealPlanningProvider layer.
CREATE OR REPLACE FUNCTION dbo.usp_usernutritiontargets_get(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT userid, targetcalories, targetproteing, targetcarbsg, targetfatsg, ismanualoverride, updatedatutc
    FROM dbo.usernutritiontargets
    WHERE userid = p_userid;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_usernutritiontargets_upsert(
    p_userid uuid,
    p_targetcalories bytea,
    p_targetproteing bytea,
    p_targetcarbsg bytea,
    p_targetfatsg bytea,
    p_ismanualoverride boolean DEFAULT false
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    INSERT INTO dbo.usernutritiontargets (userid, targetcalories, targetproteing, targetcarbsg, targetfatsg, ismanualoverride)
    VALUES (p_userid, p_targetcalories, p_targetproteing, p_targetcarbsg, p_targetfatsg, p_ismanualoverride)
    ON CONFLICT (userid) DO UPDATE SET
        targetcalories = EXCLUDED.targetcalories,
        targetproteing = EXCLUDED.targetproteing,
        targetcarbsg = EXCLUDED.targetcarbsg,
        targetfatsg = EXCLUDED.targetfatsg,
        ismanualoverride = EXCLUDED.ismanualoverride,
        updatedatutc = dbo.sysutcdatetime();

    OPEN c1 FOR
    SELECT userid, targetcalories, targetproteing, targetcarbsg, targetfatsg, ismanualoverride, updatedatutc
    FROM dbo.usernutritiontargets
    WHERE userid = p_userid;
    RETURN NEXT c1;
END $$;

-- Title/CaloriesKcal/ProteinG/CarbsG/FatsG are AES-256-GCM ciphertext,
-- encrypted/decrypted at the MealPlanningProvider layer. MealType/Status/
-- PlannedLocalTime/dates stay plaintext - not sensitive, and PlannedLocalTime/
-- LogDateUtc need to stay queryable in SQL.
CREATE OR REPLACE FUNCTION dbo.usp_meallogs_getfordate(
    p_userid uuid,
    p_logdateutc date
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT meallogid, userid, logdateutc, mealtype, title, calorieskcal, proteing, carbsg, fatsg,
           status, plannedlocaltime, loggedatutc, createdatutc, items
    FROM dbo.meallogs
    WHERE userid = p_userid AND logdateutc = p_logdateutc
    ORDER BY createdatutc ASC;
    RETURN NEXT c1;
END $$;

-- Insert when p_meallogid is NULL, otherwise update the existing row (must
-- already belong to p_userid). Stamps LoggedAtUtc the moment Status flips to
-- 'Logged' and leaves it untouched on every other write. p_items (encrypted
-- food list) is kept as-is when an update omits it, so a plain
-- Planned -> Logged flip never drops a meal's foods.
CREATE OR REPLACE FUNCTION dbo.usp_meallogs_upsert(
    p_meallogid uuid DEFAULT NULL,
    p_userid uuid DEFAULT NULL,
    p_logdateutc date DEFAULT NULL,
    p_mealtype varchar(20) DEFAULT NULL,
    p_title bytea DEFAULT NULL,
    p_calorieskcal bytea DEFAULT NULL,
    p_proteing bytea DEFAULT NULL,
    p_carbsg bytea DEFAULT NULL,
    p_fatsg bytea DEFAULT NULL,
    p_status varchar(10) DEFAULT NULL,
    p_plannedlocaltime time(0) DEFAULT NULL,
    p_items bytea DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_meallogid uuid := p_meallogid;
BEGIN
    IF v_meallogid IS NULL THEN
        v_meallogid := gen_random_uuid();

        INSERT INTO dbo.meallogs
            (meallogid, userid, logdateutc, mealtype, title, calorieskcal, proteing, carbsg, fatsg,
             status, plannedlocaltime, loggedatutc, items)
        VALUES
            (v_meallogid, p_userid, p_logdateutc, p_mealtype, p_title, p_calorieskcal, p_proteing, p_carbsg, p_fatsg,
             p_status, p_plannedlocaltime, CASE WHEN p_status = 'Logged' THEN dbo.sysutcdatetime() ELSE NULL END, p_items);
    ELSE
        -- A client-generated id that isn't stored yet creates the meal: a meal
        -- logged offline is queued with its id up front, so the upload (and
        -- any edit queued after it) can be replayed safely in order.
        INSERT INTO dbo.meallogs AS m
            (meallogid, userid, logdateutc, mealtype, title, calorieskcal, proteing, carbsg, fatsg,
             status, plannedlocaltime, loggedatutc, items)
        VALUES
            (v_meallogid, p_userid, p_logdateutc, p_mealtype, p_title, p_calorieskcal, p_proteing, p_carbsg, p_fatsg,
             p_status, p_plannedlocaltime, CASE WHEN p_status = 'Logged' THEN dbo.sysutcdatetime() ELSE NULL END, p_items)
        ON CONFLICT (meallogid) DO UPDATE
        SET logdateutc = EXCLUDED.logdateutc,
            mealtype = EXCLUDED.mealtype,
            title = EXCLUDED.title,
            calorieskcal = EXCLUDED.calorieskcal,
            proteing = EXCLUDED.proteing,
            carbsg = EXCLUDED.carbsg,
            fatsg = EXCLUDED.fatsg,
            status = EXCLUDED.status,
            plannedlocaltime = EXCLUDED.plannedlocaltime,
            items = COALESCE(EXCLUDED.items, m.items),
            loggedatutc = CASE
                WHEN EXCLUDED.status = 'Logged' AND m.loggedatutc IS NULL THEN dbo.sysutcdatetime()
                WHEN EXCLUDED.status = 'Planned' THEN NULL
                ELSE m.loggedatutc
            END
        WHERE m.userid = p_userid;
    END IF;

    OPEN c1 FOR
    SELECT meallogid, userid, logdateutc, mealtype, title, calorieskcal, proteing, carbsg, fatsg,
           status, plannedlocaltime, loggedatutc, createdatutc, items
    FROM dbo.meallogs
    WHERE meallogid = v_meallogid AND userid = p_userid;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_meallogs_delete(
    p_meallogid uuid,
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM dbo.meallogs
    WHERE meallogid = p_meallogid AND userid = p_userid;
END $$;

-- Feeds AnalyticsProvider's AvgCaloriesLogged computation (CaloriesKcal is
-- ciphertext, so it can't be aggregated in SQL) - one row per logged meal,
-- decrypted and averaged in C#.
CREATE OR REPLACE FUNCTION dbo.usp_meallogs_getcaloriesinrange(
    p_userid uuid,
    p_fromdateutc date,
    p_todateutc date
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT logdateutc, calorieskcal
    FROM dbo.meallogs
    WHERE userid = p_userid AND status = 'Logged' AND logdateutc BETWEEN p_fromdateutc AND p_todateutc;
    RETURN NEXT c1;
END $$;

-- Month-matched suggestions first, then evergreen (SuggestedMonth IS NULL)
-- ones, each group by SortOrder. MealSuggestions is system-authored content,
-- not user data, so it stays plaintext. LIMIT caps the response as a safety valve
-- for seeded content that grows over time. HasIngredients tells the weekly AI
-- plan generator which meals can back a real week-long shopping list. The
-- ingredient preview is deliberately capped at four unique ordered lines:
-- enough for AI review and the weekly recap without turning either into a full
-- recipe. Exact repeated lines are collapsed in this per-meal preview; the
-- weekly shopping list performs full quantity aggregation in the service.
CREATE OR REPLACE FUNCTION dbo.usp_mealsuggestions_getformonth(
    p_month smallint
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT ms.mealsuggestionid, ms.title, ms.mealtype, ms.description, ms.calorieskcal, ms.proteing,
           ms.carbsg, ms.fatsg, ms.suggestedmonth, ms.issystemdefault, ms.sortorder,
           ingredienttotals.ingredientcount > 0 AS hasingredients,
           ingredientpreview.ingredientpreview,
           ingredienttotals.ingredientcount
    FROM dbo.mealsuggestions ms
    CROSS JOIN LATERAL
    (
        SELECT COUNT(DISTINCT btrim(i.ingredienttext))::int AS ingredientcount
        FROM dbo.mealsuggestioningredients i
        WHERE i.mealsuggestionid = ms.mealsuggestionid
    ) ingredienttotals
    LEFT JOIN LATERAL
    (
        SELECT string_agg(g.ingredienttext, ' · ' ORDER BY g.firstsortorder) AS ingredientpreview
        FROM
        (
            SELECT btrim(i.ingredienttext) AS ingredienttext,
                   MIN(i.sortorder) AS firstsortorder
            FROM dbo.mealsuggestioningredients i
            WHERE i.mealsuggestionid = ms.mealsuggestionid
            GROUP BY btrim(i.ingredienttext)
            ORDER BY firstsortorder
            LIMIT 4
        ) g
    ) ingredientpreview ON true
    -- User-built meals are private to their diet plans, never catalog.
    WHERE ms.owneruserid IS NULL
      AND (ms.suggestedmonth = p_month OR ms.suggestedmonth IS NULL)
    ORDER BY CASE WHEN ms.suggestedmonth = p_month THEN 0 ELSE 1 END, ms.sortorder
    LIMIT 500;
    RETURN NEXT c1;
END $$;

-- =============================================================================
-- Diet plan browse/detail - the app's diet-plan library. Same visibility
-- predicate shape as usp_Splits_GetAll/usp_Splits_GetDetail (see Splits.sql):
-- system/shipped plans and Public ones are always visible, a plan the caller
-- owns or was assigned is visible to them, everything else is not. p_userid is
-- optional so the library is browseable by guests.
-- =============================================================================

CREATE OR REPLACE FUNCTION dbo.usp_dietplans_getall(
    p_userid uuid DEFAULT NULL
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
    WHERE dp.issystemdefault
       OR dp.visibility = 'Public'
       OR (p_userid IS NOT NULL AND dp.owneruserid = p_userid)
       OR (p_userid IS NOT NULL
           AND EXISTS (SELECT 1
                       FROM dbo.dietplanassignments a
                       WHERE a.dietplanid = dp.dietplanid
                         AND a.userid = p_userid))
    ORDER BY dp.sortorder
    LIMIT 2500;
    RETURN NEXT c1;
END $$;

-- Result set 1: plan header. Result set 2: its days. Result set 3: each day's
-- meal slots with the referenced MealSuggestions row. Result set 4: the
-- ingredient lines behind those meal suggestions, in plan order, for the
-- week-long shopping list. All four are always emitted (empty when invisible),
-- same convention as usp_Splits_GetDetail.
CREATE OR REPLACE FUNCTION dbo.usp_dietplans_getdetail(
    p_dietplanid uuid,
    p_userid uuid DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    c2 refcursor;
    c3 refcursor;
    c4 refcursor;
    v_visible boolean;
BEGIN
    v_visible := EXISTS (
        SELECT 1
        FROM dbo.nutritionplans dp
        WHERE dp.dietplanid = p_dietplanid
          AND (dp.issystemdefault
               OR dp.visibility = 'Public'
               OR (p_userid IS NOT NULL AND dp.owneruserid = p_userid)
               OR (p_userid IS NOT NULL
                   AND EXISTS (SELECT 1
                               FROM dbo.dietplanassignments a
                               WHERE a.dietplanid = dp.dietplanid
                                 AND a.userid = p_userid))));

    OPEN c1 FOR
    SELECT dietplanid, name, description, heroimageurl, periodtype, durationdays,
           issystemdefault, sortorder, visibility, owneruserid, isaigenerated, aikeptatutc
    FROM dbo.nutritionplans
    WHERE dietplanid = p_dietplanid
      AND v_visible;
    RETURN NEXT c1;

    OPEN c2 FOR
    SELECT dietplandayid, dayindex, title
    FROM dbo.dietplandays
    WHERE dietplanid = p_dietplanid
      AND v_visible
    ORDER BY dayindex;
    RETURN NEXT c2;

    OPEN c3 FOR
    SELECT d.dietplandayid, m.dietplanmealid, m.mealtype, ms.mealsuggestionid, ms.title, ms.description,
           ms.calorieskcal, ms.proteing, ms.carbsg, ms.fatsg, m.sortorder
    FROM dbo.dietplandays d
    INNER JOIN dbo.dietplanmeals m ON m.dietplandayid = d.dietplandayid
    INNER JOIN dbo.mealsuggestions ms ON ms.mealsuggestionid = m.mealsuggestionid
    WHERE d.dietplanid = p_dietplanid
      AND v_visible
    ORDER BY d.dayindex, m.sortorder;
    RETURN NEXT c3;

    OPEN c4 FOR
    SELECT i.ingredienttext
    FROM dbo.dietplandays d
    INNER JOIN dbo.dietplanmeals m ON m.dietplandayid = d.dietplandayid
    INNER JOIN dbo.mealsuggestioningredients i ON i.mealsuggestionid = m.mealsuggestionid
    WHERE d.dietplanid = p_dietplanid
      AND v_visible
    ORDER BY d.dayindex, m.sortorder, i.sortorder;
    RETURN NEXT c4;
END $$;
