-- Search values are always bound parameters (never concatenated into the
-- command text), so the LIKE usage below carries no injection risk.
-- p_musclegroups is a comma-separated list of the catalogue's coarse muscle
-- groups (chest/back/legs/shoulders/arms/core). Splitting it keeps the filter
-- set-based, so one round trip can scope a search or a suggestion read to every
-- group a day's title points at (e.g. "Chest & Triceps" -> chest,arms).
--
-- p_searchtermsjson is the typed search already broken into keyword groups by
-- the API (ExerciseSearchTerms): [{"g":0,"t":"shoulder"},{"g":0,"t":"delt"},
-- {"g":1,"t":"fly"}] - one row per spelling, g = the typed word it stands for.
-- A word counts as matched when any of its spellings is in the name (or the
-- name with spaces/hyphens removed, so "pullup" finds "Pull-Up"), the muscle
-- group or the equipment. Exercises must hit at least half the words, one of
-- them in the name, and rank by words hit, then the whole typed phrase, then
-- name hits, then the shortest (most canonical) name - so "shoulder fly" finds
-- "Shoulder Cable Flys" first, followed by the other shoulder flys.
-- With no keywords (the suggestion reads, or a search of only filler words)
-- it falls back to the plain substring match on p_searchtext.
--
-- p_userid adds that user's own exercises (CreatedByUserId) to the shared
-- catalogue; NULL - the suggestion list and the weekly plan generator - reads
-- the catalogue alone. IsCustom tells the picker which rows are the user's.
-- LIMIT caps an anonymous, unbounded-in-principle search over the exercise catalogue.
CREATE OR REPLACE FUNCTION dbo.usp_exercises_search(
    p_musclegroups varchar(200) DEFAULT NULL,
    p_searchtext varchar(150) DEFAULT NULL,
    p_searchtermsjson text DEFAULT NULL,
    p_userid uuid DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_phrase varchar(150) COLLATE ci := NULLIF(btrim(p_searchtext), '');
    v_terms jsonb := '[]'::jsonb;
    v_groupcount integer;
BEGIN
    IF p_searchtermsjson IS NOT NULL AND p_searchtermsjson IS JSON ARRAY THEN
        SELECT COALESCE(jsonb_agg(jsonb_build_object('g', t.g, 't', t.t)), '[]')
        INTO v_terms
        FROM jsonb_to_recordset(p_searchtermsjson::jsonb) AS t(g integer, t varchar(60))
        WHERE t.g IS NOT NULL AND t.t IS NOT NULL AND char_length(rtrim(t.t)) > 0;
    END IF;

    SELECT COUNT(DISTINCT (e->>'g')::int) INTO v_groupcount FROM jsonb_array_elements(v_terms) e;

    IF v_groupcount = 0 THEN
        OPEN c1 FOR
        SELECT exerciseid, name, musclegroup, equipmenttype, iscompound, demovideourl,
               (createdbyuserid IS NOT NULL) AS iscustom
        FROM dbo.exercises
        WHERE (createdbyuserid IS NULL OR createdbyuserid = p_userid)
          AND (p_musclegroups IS NULL
               OR musclegroup IN (SELECT btrim(value) FROM string_to_table(NULLIF(p_musclegroups, ''), ',') AS value))
          AND (v_phrase IS NULL OR name LIKE '%' || v_phrase || '%')
        ORDER BY name
        LIMIT 200;
        RETURN NEXT c1;
        RETURN;
    END IF;

    OPEN c1 FOR
    WITH terms AS
    (
        SELECT (e->>'g')::int AS groupindex, (e->>'t')::varchar(60) COLLATE ci AS term
        FROM jsonb_array_elements(v_terms) e
    ),
    candidates AS
    (
        SELECT exerciseid, name, musclegroup, equipmenttype, iscompound, demovideourl,
               (createdbyuserid IS NOT NULL) AS iscustom,
               replace(replace(name, '-', ''), ' ', '') AS squashedname
        FROM dbo.exercises
        WHERE (createdbyuserid IS NULL OR createdbyuserid = p_userid)
          AND (p_musclegroups IS NULL
               OR musclegroup IN (SELECT btrim(value) FROM string_to_table(NULLIF(p_musclegroups, ''), ',') AS value))
    ),
    wordhits AS
    (
        SELECT c.exerciseid, t.groupindex,
               MAX(CASE WHEN c.name LIKE '%' || t.term || '%'
                          OR c.squashedname LIKE '%' || t.term || '%' THEN 1 ELSE 0 END) AS inname,
               MAX(CASE WHEN c.name LIKE '%' || t.term || '%'
                          OR c.squashedname LIKE '%' || t.term || '%'
                          OR c.musclegroup LIKE '%' || t.term || '%'
                          OR c.equipmenttype LIKE '%' || t.term || '%' THEN 1 ELSE 0 END) AS anywhere
        FROM candidates c
        CROSS JOIN terms t
        GROUP BY c.exerciseid, t.groupindex
    ),
    scored AS
    (
        SELECT exerciseid, SUM(anywhere) AS wordsmatched, SUM(inname) AS namewordsmatched
        FROM wordhits
        GROUP BY exerciseid
    )
    SELECT c.exerciseid, c.name, c.musclegroup, c.equipmenttype, c.iscompound, c.demovideourl, c.iscustom
    FROM scored s
    INNER JOIN candidates c ON c.exerciseid = s.exerciseid
    WHERE s.namewordsmatched >= 1
      AND s.wordsmatched * 2 >= v_groupcount
    ORDER BY s.wordsmatched DESC,
             CASE WHEN v_phrase IS NOT NULL AND c.name LIKE '%' || v_phrase || '%' THEN 0 ELSE 1 END,
             s.namewordsmatched DESC,
             char_length(rtrim(c.name)),
             c.name
    LIMIT 200;
    RETURN NEXT c1;
END $$;

-- Every exercise the user can pick (the catalogue plus their own), for the
-- "did you mean" pass ExerciseCloseMatches runs in the API when a search finds
-- nothing - typo tolerance needs edit distances the LIKE search above can't do.
-- Only the name-matching columns plus what a picker row shows.
CREATE OR REPLACE FUNCTION dbo.usp_exercises_getpickable(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT exerciseid, name, musclegroup, equipmenttype, iscompound, demovideourl,
           (createdbyuserid IS NOT NULL) AS iscustom
    FROM dbo.exercises
    WHERE createdbyuserid IS NULL OR createdbyuserid = p_userid;
    RETURN NEXT c1;
END $$;

-- An exercise the user couldn't find, added from the exercise picker; private
-- to them. A name they already have, or one the catalogue already has (same
-- name ignoring case, spaces and hyphens), returns that row instead of adding
-- a duplicate, so a retried save or a near-miss search can't fork the list.
CREATE OR REPLACE FUNCTION dbo.usp_exercises_createcustom(
    p_userid uuid,
    p_name varchar(150),
    p_musclegroup varchar(30),
    p_equipmenttype varchar(50) DEFAULT NULL,
    p_iscompound boolean DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_squashed varchar(150) COLLATE ci := replace(replace(p_name, '-', ''), ' ', '');
    v_exerciseid uuid;
BEGIN
    -- Serialises concurrent saves by the same user so a double-tap can't add the row twice.
    PERFORM pg_advisory_xact_lock(hashtextextended('exercise-custom:' || p_userid::text, 0));

    SELECT exerciseid INTO v_exerciseid
    FROM dbo.exercises
    WHERE (createdbyuserid IS NULL OR createdbyuserid = p_userid)
      AND replace(replace(name, '-', ''), ' ', '') = v_squashed
    ORDER BY CASE WHEN createdbyuserid IS NULL THEN 0 ELSE 1 END
    LIMIT 1;

    IF v_exerciseid IS NULL THEN
        v_exerciseid := gen_random_uuid();
        INSERT INTO dbo.exercises (exerciseid, name, musclegroup, equipmenttype, iscompound, createdbyuserid)
        VALUES (v_exerciseid, p_name, p_musclegroup, p_equipmenttype, p_iscompound, p_userid);
    END IF;

    OPEN c1 FOR
    SELECT exerciseid, name, musclegroup, equipmenttype, iscompound, demovideourl,
           (createdbyuserid IS NOT NULL) AS iscustom
    FROM dbo.exercises
    WHERE exerciseid = v_exerciseid;
    RETURN NEXT c1;
END $$;
