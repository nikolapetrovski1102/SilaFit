-- p_query is expected pre-normalized by the caller (FoodService applies the
-- same lower-case/punctuation folding the importer used for NormalizedName);
-- the lower/trim here is only a safety net for direct callers.
-- p_userid scopes user-added foods (CreatedByUserId): the caller sees the
-- shared catalog plus only their own additions.
-- Ranking: the caller's own foods, then generic reference foods, then
-- branded products collapsed to one row per name and brand.
--
-- NormalizedName uses the "C" collation (it is always stored lower-case), so
-- the >= / < prefix range below is a plain btree range scan.
CREATE OR REPLACE FUNCTION dbo.foodnutrition_search(
    p_query varchar(200),
    p_take integer DEFAULT 25,
    p_userid uuid DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_query text;
    v_take integer;
    v_matches bigint[] := '{}'::bigint[];
    v_escaped text;
    v_prefix text;
    v_primaryprefix text;
    v_pluralprimaryprefix text;
    v_lastcodepoint integer;
    v_upperbound text;
    v_remaining integer;
BEGIN
    v_query := lower(btrim(COALESCE(p_query, '')));
    v_query := translate(v_query, ',.-/()', '      ');
    WHILE strpos(v_query, '  ') > 0 LOOP
        v_query := replace(v_query, '  ', ' ');
    END LOOP;
    v_take := CASE WHEN p_take BETWEEN 1 AND 100 THEN p_take ELSE 25 END;

    IF translate(v_query, '0123456789', '') = '' THEN
        v_matches := ARRAY(
            SELECT foodnutritionid
            FROM dbo.foodnutrition
            WHERE barcode = v_query
              AND (createdbyuserid IS NULL OR createdbyuserid = p_userid)
            ORDER BY sourcepriority, foodnutritionid
            LIMIT v_take);
    ELSIF char_length(v_query) >= 2 THEN
        v_escaped := replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_');
        v_prefix := v_escaped || '%';
        -- "Egg, whole, raw": USDA/CNF/CoFID name the plain food as the query
        -- followed by a comma, while "Egg burrito" is a dish that contains it.
        -- The plural counts too: "oat" should find "Oats, rolled".
        v_primaryprefix := v_escaped || ',%';
        v_pluralprimaryprefix := v_escaped || 's,%';
        -- Next lexical prefix ("egg" -> "egh") bounds the range scan.
        v_lastcodepoint := ascii(right(v_query, 1));
        v_upperbound := left(v_query, -1) || chr(CASE WHEN v_lastcodepoint + 1 BETWEEN 55296 AND 57343
                                                      THEN 57344 ELSE v_lastcodepoint + 1 END);

        -- 1. The caller's own foods, exact name then prefix.
        IF p_userid IS NOT NULL THEN
            v_matches := v_matches || ARRAY(
                SELECT foodnutritionid
                FROM dbo.foodnutrition
                WHERE createdbyuserid = p_userid
                  AND normalizedname >= v_query AND normalizedname < v_upperbound
                  AND normalizedname LIKE v_prefix
                ORDER BY CASE WHEN normalizedname = v_query THEN 0 ELSE 1 END,
                    normalizedname, namelength, foodnutritionid
                LIMIT v_take);
        END IF;

        -- 2. Generic reference foods (ix_foodnutrition_generic, ~1% of the
        -- catalog, so reading the whole prefix range to rank it is cheap),
        -- one row per name from the best source: the exact name and the
        -- "<query>, ..." plain food. Dishes that merely start with the query
        -- ("Nutella sandwich") wait until after exact branded matches.
        v_remaining := v_take - cardinality(v_matches);
        IF v_remaining > 0 THEN
            v_matches := v_matches || ARRAY(
                SELECT ranked.foodnutritionid
                FROM
                (
                    SELECT foodnutritionid, namelength,
                        CASE WHEN normalizedname = v_query THEN 0
                             WHEN name LIKE v_primaryprefix
                               OR name LIKE v_pluralprimaryprefix THEN 1
                             ELSE 2 END AS tier,
                        ROW_NUMBER() OVER (
                            PARTITION BY normalizedname
                            ORDER BY CASE sourcename
                                WHEN 'USDA Foundation' THEN 0 WHEN 'USDA Survey' THEN 1
                                WHEN 'CNF' THEN 2 WHEN 'CoFID' THEN 3 ELSE 4 END,
                                foodnutritionid) AS namerank
                    FROM dbo.foodnutrition
                    WHERE sourcename IN ('USDA Foundation', 'USDA Survey', 'CNF', 'CoFID', 'USDA Legacy')
                      AND normalizedname >= v_query AND normalizedname < v_upperbound
                      AND normalizedname LIKE v_prefix
                ) ranked
                WHERE ranked.namerank = 1 AND ranked.tier < 2
                ORDER BY ranked.tier, ranked.namelength, ranked.foodnutritionid
                LIMIT v_remaining);
        END IF;

        -- 3. Branded products, one row per (name, brand): Open Food Facts and
        -- USDA Branded carry the same product many times over, and dozens of
        -- brands sell something named just "Egg". Exact name here, prefix in
        -- step 5 - kept as two reads so the prefix read stops early in index
        -- order instead of sorting the whole range.
        v_remaining := v_take - cardinality(v_matches);
        IF v_remaining > 0 THEN
            v_matches := v_matches || ARRAY(
                SELECT ranked.foodnutritionid
                FROM
                (
                    SELECT foodnutritionid, sourcename, namelength,
                        ROW_NUMBER() OVER (
                            PARTITION BY lower(COALESCE(brandname, ''))
                            ORDER BY CASE sourcename WHEN 'USDA Branded' THEN 0 ELSE 1 END, foodnutritionid) AS brandrank
                    FROM dbo.foodnutrition
                    WHERE normalizedname = v_query
                      AND sourcename IN ('USDA Branded', 'Open Food Facts')
                      AND createdbyuserid IS NULL
                ) ranked
                WHERE ranked.brandrank = 1
                ORDER BY CASE ranked.sourcename WHEN 'USDA Branded' THEN 0 ELSE 1 END,
                    ranked.namelength, ranked.foodnutritionid
                LIMIT v_remaining);
        END IF;

        -- 4. Generic dishes that start with the query.
        v_remaining := v_take - cardinality(v_matches);
        IF v_remaining > 0 THEN
            v_matches := v_matches || ARRAY(
                SELECT ranked.foodnutritionid
                FROM
                (
                    SELECT foodnutritionid, namelength,
                        CASE WHEN normalizedname = v_query THEN 0
                             WHEN name LIKE v_primaryprefix
                               OR name LIKE v_pluralprimaryprefix THEN 1
                             ELSE 2 END AS tier,
                        ROW_NUMBER() OVER (
                            PARTITION BY normalizedname
                            ORDER BY CASE sourcename
                                WHEN 'USDA Foundation' THEN 0 WHEN 'USDA Survey' THEN 1
                                WHEN 'CNF' THEN 2 WHEN 'CoFID' THEN 3 ELSE 4 END,
                                foodnutritionid) AS namerank
                    FROM dbo.foodnutrition
                    WHERE sourcename IN ('USDA Foundation', 'USDA Survey', 'CNF', 'CoFID', 'USDA Legacy')
                      AND normalizedname >= v_query AND normalizedname < v_upperbound
                      AND normalizedname LIKE v_prefix
                ) ranked
                WHERE ranked.namerank = 1 AND ranked.tier = 2
                ORDER BY ranked.namelength, ranked.foodnutritionid
                LIMIT v_remaining);
        END IF;

        -- 5. Branded products by prefix. Over-read in index order, then
        -- collapse duplicates.
        v_remaining := v_take - cardinality(v_matches);
        IF v_remaining > 0 THEN
            v_matches := v_matches || ARRAY(
                SELECT ranked.foodnutritionid
                FROM
                (
                    SELECT candidate.foodnutritionid, candidate.normalizedname,
                        ROW_NUMBER() OVER (
                            PARTITION BY candidate.normalizedname, lower(COALESCE(candidate.brandname, ''))
                            ORDER BY CASE candidate.sourcename WHEN 'USDA Branded' THEN 0 ELSE 1 END,
                                candidate.foodnutritionid) AS brandrank
                    FROM
                    (
                        SELECT foodnutritionid, normalizedname, brandname, sourcename
                        FROM dbo.foodnutrition
                        WHERE normalizedname >= v_query AND normalizedname < v_upperbound
                          AND normalizedname LIKE v_prefix
                          AND normalizedname <> v_query
                          AND sourcename IN ('USDA Branded', 'Open Food Facts')
                          AND createdbyuserid IS NULL
                        ORDER BY normalizedname, foodnutritionid
                        LIMIT v_remaining * 4
                    ) candidate
                ) ranked
                WHERE ranked.brandrank = 1
                ORDER BY ranked.normalizedname, ranked.foodnutritionid
                LIMIT v_remaining);
        END IF;
    END IF;

    OPEN c1 FOR
    SELECT
        food.foodnutritionid,
        food.name,
        food.brandname,
        food.barcode,
        food.sourcename,
        food.servingsizeg,
        food.calorieskcal,
        food.proteing,
        food.carbohydrateg,
        food.fatg,
        food.fiberg,
        food.sugarg,
        food.sodiummg,
        food.createdbyuserid IS NOT NULL AS iscustom
    FROM unnest(v_matches) WITH ORDINALITY AS matches(foodnutritionid, resultorder)
    INNER JOIN dbo.foodnutrition food ON food.foodnutritionid = matches.foodnutritionid
    ORDER BY matches.resultorder;
    RETURN NEXT c1;
END $$;

-- A food the user couldn't find in the catalog, added from the meal tracker.
-- Nutrients are per 100 g like every other row. p_contenthash is computed by
-- FoodService from the new SourceFoodId so it can never collide with
-- (or be deduplicated into) a catalog row or another user's food.
CREATE OR REPLACE FUNCTION dbo.foodnutrition_createcustom(
    p_userid uuid,
    p_name varchar(500),
    p_normalizedname varchar(500),
    p_brandname varchar(300) DEFAULT NULL,
    p_servingsizeg numeric(12,3) DEFAULT NULL,
    p_calorieskcal numeric(12,3) DEFAULT NULL,
    p_proteing numeric(12,3) DEFAULT NULL,
    p_carbohydrateg numeric(12,3) DEFAULT NULL,
    p_fatg numeric(12,3) DEFAULT NULL,
    p_fiberg numeric(12,3) DEFAULT NULL,
    p_sugarg numeric(12,3) DEFAULT NULL,
    p_sodiummg numeric(12,3) DEFAULT NULL,
    p_sourcefoodid varchar(120) DEFAULT NULL,
    p_contenthash bytea DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_foodnutritionid bigint;
BEGIN
    INSERT INTO dbo.foodnutrition
        (name, normalizedname, brandname, sourcename, sourcefoodid, servingsizeg,
         calorieskcal, proteing, carbohydrateg, fatg, fiberg, sugarg, sodiummg,
         isbranded, contenthash, createdbyuserid)
    VALUES
        (p_name, p_normalizedname, p_brandname, 'User', p_sourcefoodid, p_servingsizeg,
         p_calorieskcal, p_proteing, p_carbohydrateg, p_fatg, p_fiberg, p_sugarg, p_sodiummg,
         p_brandname IS NOT NULL, p_contenthash, p_userid)
    RETURNING foodnutritionid INTO v_foodnutritionid;

    OPEN c1 FOR
    SELECT
        foodnutritionid,
        name,
        brandname,
        barcode,
        sourcename,
        servingsizeg,
        calorieskcal,
        proteing,
        carbohydrateg,
        fatg,
        fiberg,
        sugarg,
        sodiummg,
        true AS iscustom
    FROM dbo.foodnutrition
    WHERE foodnutritionid = v_foodnutritionid;
    RETURN NEXT c1;
END $$;

-- Removes branded catalog rows that add noise without adding a food:
-- incomplete, physically implausible, unidentifiable, or a duplicate of a
-- row already kept. Generic reference sources and user-created foods are
-- never touched. Meal logs snapshot their macros (MealLogs.Items), so no
-- logged meal changes when a catalog row goes.
--
-- Runs at the end of every Silen.Tools.ImportFoodNutrition run (the upsert
-- there re-inserts rows this deleted, so the rules have to re-apply); the
-- importer also skips the per-row cases up front (FoodNutritionRow.IsCatalogQuality)
-- - keep the two in step. p_dryrun = true only reports what would go.
-- p_batchsize is kept for call compatibility; PostgreSQL deletes the whole set
-- in one statement inside the caller's transaction.
CREATE OR REPLACE FUNCTION dbo.foodnutrition_prune(
    p_dryrun boolean DEFAULT true,
    p_batchsize integer DEFAULT 20000
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_ids bigint[];
    v_reasons smallint[];
BEGIN
    WITH branded AS (
        SELECT foodnutritionid, sourcename, brandname, normalizedname, calorieskcal,
               proteing, carbohydrateg, fatg,
               4 * proteing + 4 * carbohydrateg + 9 * fatg AS atwater
        FROM dbo.foodnutrition
        WHERE sourcename IN ('USDA Branded', 'Open Food Facts')
          AND createdbyuserid IS NULL
    ),
    -- 1-4: per-row rules, branded sources only.
    perrow AS (
        SELECT foodnutritionid,
            (CASE
                -- 1. Can't be tracked without all four headline values.
                WHEN calorieskcal IS NULL OR proteing IS NULL OR carbohydrateg IS NULL OR fatg IS NULL THEN 1
                -- 2. Energy the macros can't account for. Below the macros:
                -- sugar-free (polyol) and high-fibre products legitimately land
                -- well under 4 kcal/g of carbs, so only under half is an error
                -- ("condensed milk, 3 kcal"). Above them is allowed up to
                -- ~300 kcal, which alcohol (7 kcal/g, spirits) explains - beyond
                -- that it's usually kJ typed as kcal.
                WHEN atwater - calorieskcal > 50 AND calorieskcal < 0.5 * atwater THEN 2
                WHEN calorieskcal - atwater > 300 THEN 2
                -- 3. An Open Food Facts product with no brand can't be told
                -- apart from the dozens of same-named rows around it.
                WHEN sourcename = 'Open Food Facts' AND NULLIF(btrim(brandname), '') IS NULL THEN 3
                -- 4. Name is only digits (usually a barcode typed into the name).
                WHEN translate(normalizedname, '0123456789 ', '') = '' THEN 4
            END)::smallint AS reason
        FROM branded
        WHERE calorieskcal IS NULL OR proteing IS NULL OR carbohydrateg IS NULL OR fatg IS NULL
           OR (atwater - calorieskcal > 50 AND calorieskcal < 0.5 * atwater)
           OR calorieskcal - atwater > 300
           OR (sourcename = 'Open Food Facts' AND NULLIF(btrim(brandname), '') IS NULL)
           OR translate(normalizedname, '0123456789 ', '') = ''
    ),
    -- 5. Duplicates: the same name with the same macros (to the gram/kcal)
    -- is the same food to someone logging it, whatever the brand spelling or
    -- pack size. Generic rows win, then USDA Branded, then the oldest row;
    -- only branded losers are removed.
    duplicates AS (
        SELECT ranked.foodnutritionid, 5::smallint AS reason
        FROM
        (
            SELECT food.foodnutritionid, food.sourcename,
                ROW_NUMBER() OVER (
                    PARTITION BY food.normalizedname, round(food.calorieskcal, 0), round(food.proteing, 0),
                                 round(food.carbohydrateg, 0), round(food.fatg, 0)
                    ORDER BY food.sourcepriority, food.foodnutritionid) AS duplicaterank
            FROM dbo.foodnutrition food
            WHERE food.createdbyuserid IS NULL
              AND food.calorieskcal IS NOT NULL AND food.proteing IS NOT NULL
              AND food.carbohydrateg IS NOT NULL AND food.fatg IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM perrow p WHERE p.foodnutritionid = food.foodnutritionid)
        ) ranked
        WHERE ranked.duplicaterank > 1
          AND ranked.sourcename IN ('USDA Branded', 'Open Food Facts')
    ),
    doomed AS (
        SELECT foodnutritionid, reason FROM perrow
        UNION ALL
        SELECT foodnutritionid, reason FROM duplicates
    )
    SELECT COALESCE(array_agg(foodnutritionid), '{}'), COALESCE(array_agg(reason), '{}')
    INTO v_ids, v_reasons
    FROM doomed;

    OPEN c1 FOR
    SELECT
        CASE d.reason
            WHEN 1 THEN 'Missing calories/protein/carbs/fat'
            WHEN 2 THEN 'Calories inconsistent with macros'
            WHEN 3 THEN 'Open Food Facts product without a brand'
            WHEN 4 THEN 'Name is only digits'
            WHEN 5 THEN 'Duplicate name + macros'
        END AS reason,
        COUNT(*) AS rowsremoved
    FROM unnest(v_reasons) AS d(reason)
    GROUP BY d.reason
    ORDER BY d.reason;
    RETURN NEXT c1;

    IF p_dryrun THEN
        RETURN;
    END IF;

    DELETE FROM dbo.foodnutrition food
    USING unnest(v_ids) AS d(foodnutritionid)
    WHERE food.foodnutritionid = d.foodnutritionid
      AND food.createdbyuserid IS NULL;
END $$;
