-- App-facing CRUD for a user's own custom split, mirroring AdminSplits.sql's
-- shape (same Outcome/EntityId/Detail result, same validation ranges) but with
-- a single, simple ownership rule instead of the trainer/manage_all one: a
-- user may only write a split whose workoutsplits.owneruserid is themselves,
-- checked inside the same transaction as the write, same as the admin
-- functions. No AdminAuditLog rows - there is no user-facing audit trail in
-- this codebase today.

CREATE OR REPLACE FUNCTION dbo.usp_usersplits_getowned(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT s.splitid,
           s.name,
           s.category,
           s.level,
           s.durationdays,
           s.description,
           s.heroimageurl,
           s.issystemdefault,
           s.sortorder,
           s.recommendedgoal,
           s.visibility,
           s.daysperweek,
           s.programdurationweeks,
           s.minsessionminutes,
           s.maxsessionminutes,
           s.equipmentrequired,
           s.targetgender,
           s.workouttypelabel,
           s.sourcecategoriesjson,
           s.owneruserid,
           s.isaigenerated,
           s.aikeptatutc,
           COALESCE((SELECT trunc(AVG(d.estimatedminutes))::int
                     FROM dbo.splitdays d
                     WHERE d.splitid = s.splitid
                       AND NOT d.isrestday), 0) AS avgsessionminutes
    FROM dbo.workoutsplits s
    WHERE s.owneruserid = p_userid
    ORDER BY s.sortorder, s.name;
    RETURN NEXT c1;
END $$;

-- p_isaigenerated is only ever passed true by
-- Silen.Tools.WeeklyPlanGeneration; the manual builder always leaves it at
-- its false default. On UPDATE the flag is deliberately left untouched -
-- editing an AI-generated split by hand doesn't strip its AI provenance, and
-- the weekly job only ever updates a row it created itself.
CREATE OR REPLACE FUNCTION dbo.usp_usersplit_upsert(
    p_splitid uuid DEFAULT NULL,
    p_userid uuid DEFAULT NULL,
    p_name text DEFAULT NULL,
    p_category text DEFAULT NULL,
    p_level text DEFAULT NULL,
    p_durationdays smallint DEFAULT NULL,
    p_description text DEFAULT NULL,
    p_heroimageurl text DEFAULT NULL,
    p_recommendedgoal text DEFAULT NULL,
    p_isaigenerated boolean DEFAULT false
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_splitid uuid := p_splitid;
    v_name text := btrim(p_name);
    v_category text := btrim(p_category);
    v_level text := btrim(p_level);
    v_description text := NULLIF(btrim(p_description), '');
    v_heroimageurl text := NULLIF(btrim(p_heroimageurl), '');
    v_recommendedgoal text := NULLIF(btrim(p_recommendedgoal), '');
BEGIN
    IF v_name IS NULL OR v_name = '' THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A split name is required.');
        RETURN;
    END IF;

    IF p_durationdays < 1 OR p_durationdays > 14 THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A split lasts between 1 and 14 days.');
        RETURN;
    END IF;

    IF v_splitid IS NULL THEN
        v_splitid := gen_random_uuid();

        -- Always Private on create: this is the user's own content, not
        -- something to publish. Visibility is not an app-exposed concept for
        -- user-owned splits - only owneruserid gates who can see/edit it.
        INSERT INTO dbo.workoutsplits
            (splitid, name, category, level, durationdays, description, heroimageurl, recommendedgoal,
             issystemdefault, sortorder, visibility, owneruserid, isaigenerated)
        VALUES
            (v_splitid, v_name, v_category, v_level, p_durationdays, v_description, v_heroimageurl, v_recommendedgoal,
             false, 0, 'Private', p_userid, p_isaigenerated);
    ELSE
        IF NOT EXISTS (SELECT 1 FROM dbo.workoutsplits WHERE splitid = v_splitid) THEN
            RETURN NEXT dbo.outcome_cursor(1, v_splitid, 'That split no longer exists.');
            RETURN;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM dbo.workoutsplits WHERE splitid = v_splitid AND owneruserid = p_userid) THEN
            RETURN NEXT dbo.outcome_cursor(2, v_splitid, 'You can only edit splits you built yourself.');
            RETURN;
        END IF;

        UPDATE dbo.workoutsplits
        SET name = v_name,
            category = v_category,
            level = v_level,
            durationdays = p_durationdays,
            description = v_description,
            heroimageurl = v_heroimageurl,
            recommendedgoal = v_recommendedgoal
        WHERE splitid = v_splitid;
    END IF;

    RETURN NEXT dbo.outcome_cursor(0, v_splitid, NULL);
END $$;

-- Blocked outright while any user has the split active (same guard as
-- usp_Admin_Split_Delete) - a split can only be owneruserid-owned by one
-- person, but that person themselves may have it active, and deleting out
-- from under their own active workout is still a footgun worth preventing.
CREATE OR REPLACE FUNCTION dbo.usp_usersplit_delete(
    p_splitid uuid,
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_name text;
BEGIN
    SELECT name INTO v_name FROM dbo.workoutsplits WHERE splitid = p_splitid;

    IF v_name IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_splitid, 'That split no longer exists.');
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM dbo.workoutsplits WHERE splitid = p_splitid AND owneruserid = p_userid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_splitid, 'You can only delete splits you built yourself.');
        RETURN;
    END IF;

    IF EXISTS (SELECT 1 FROM dbo.useractivesplits WHERE splitid = p_splitid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_splitid,
            '''' || v_name || ''' is your active split - switch to another split before deleting it.');
        RETURN;
    END IF;

    DELETE FROM dbo.splitdayexercises
    WHERE splitdayid IN (SELECT splitdayid FROM dbo.splitdays WHERE splitid = p_splitid);

    DELETE FROM dbo.splitdays WHERE splitid = p_splitid;
    DELETE FROM dbo.workoutsplits WHERE splitid = p_splitid;

    RETURN NEXT dbo.outcome_cursor(0, p_splitid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_usersplitday_upsert(
    p_splitdayid uuid DEFAULT NULL,
    p_splitid uuid DEFAULT NULL,
    p_userid uuid DEFAULT NULL,
    p_dayindex smallint DEFAULT NULL,
    p_title text DEFAULT NULL,
    p_focuslabel text DEFAULT NULL,
    p_estimatedminutes smallint DEFAULT 45,
    p_isrestday boolean DEFAULT false
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_splitdayid uuid := p_splitdayid;
    v_title text := btrim(p_title);
    v_focuslabel text := NULLIF(btrim(p_focuslabel), '');
    v_splitname text;
BEGIN
    SELECT name INTO v_splitname FROM dbo.workoutsplits WHERE splitid = p_splitid;

    IF v_splitname IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_splitid, 'That split no longer exists.');
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM dbo.workoutsplits WHERE splitid = p_splitid AND owneruserid = p_userid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_splitid, 'You can only edit splits you built yourself.');
        RETURN;
    END IF;

    IF v_title IS NULL OR v_title = '' THEN
        RETURN NEXT dbo.outcome_cursor(3, p_splitid, 'A day title is required.');
        RETURN;
    END IF;

    IF p_dayindex < 1 OR p_dayindex > 14 THEN
        RETURN NEXT dbo.outcome_cursor(3, p_splitid, 'Day index must be between 1 and 14.');
        RETURN;
    END IF;

    IF p_estimatedminutes < 1 OR p_estimatedminutes > 600 THEN
        RETURN NEXT dbo.outcome_cursor(3, p_splitid, 'Estimated minutes must be between 1 and 600.');
        RETURN;
    END IF;

    IF EXISTS (SELECT 1
               FROM dbo.splitdays
               WHERE splitid = p_splitid
                 AND dayindex = p_dayindex
                 AND (v_splitdayid IS NULL OR splitdayid <> v_splitdayid)) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_splitid,
            'Day ' || p_dayindex::text || ' already exists in ''' || v_splitname || '''.');
        RETURN;
    END IF;

    IF v_splitdayid IS NULL THEN
        v_splitdayid := gen_random_uuid();

        INSERT INTO dbo.splitdays (splitdayid, splitid, dayindex, title, focuslabel, estimatedminutes, isrestday)
        VALUES (v_splitdayid, p_splitid, p_dayindex, v_title, v_focuslabel, p_estimatedminutes, p_isrestday);
    ELSE
        UPDATE dbo.splitdays
        SET dayindex = p_dayindex,
            title = v_title,
            focuslabel = v_focuslabel,
            estimatedminutes = p_estimatedminutes,
            isrestday = p_isrestday
        WHERE splitdayid = v_splitdayid
          AND splitid = p_splitid;

        IF NOT FOUND THEN
            RETURN NEXT dbo.outcome_cursor(1, v_splitdayid, 'That day no longer exists on this split.');
            RETURN;
        END IF;
    END IF;

    RETURN NEXT dbo.outcome_cursor(0, v_splitdayid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_usersplitday_delete(
    p_splitdayid uuid,
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_title text;
BEGIN
    SELECT d.title INTO v_title
    FROM dbo.splitdays d
    INNER JOIN dbo.workoutsplits s ON s.splitid = d.splitid
    WHERE d.splitdayid = p_splitdayid;

    IF v_title IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_splitdayid, 'That day no longer exists.');
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM dbo.splitdays d
                   INNER JOIN dbo.workoutsplits s ON s.splitid = d.splitid
                   WHERE d.splitdayid = p_splitdayid
                     AND s.owneruserid = p_userid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_splitdayid, 'You can only edit splits you built yourself.');
        RETURN;
    END IF;

    DELETE FROM dbo.splitdayexercises WHERE splitdayid = p_splitdayid;
    DELETE FROM dbo.splitdays WHERE splitdayid = p_splitdayid;

    RETURN NEXT dbo.outcome_cursor(0, p_splitdayid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_usersplitdayexercise_upsert(
    p_splitdayexerciseid uuid DEFAULT NULL,
    p_splitdayid uuid DEFAULT NULL,
    p_userid uuid DEFAULT NULL,
    p_exerciseid uuid DEFAULT NULL,
    p_sortorder smallint DEFAULT 0,
    p_targetsets smallint DEFAULT NULL,
    p_targetrepslow smallint DEFAULT NULL,
    p_targetrepshigh smallint DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_splitdayexerciseid uuid := p_splitdayexerciseid;
    v_exercisename text;
    v_daytitle text;
BEGIN
    -- Another user's private exercise is treated as missing.
    SELECT name INTO v_exercisename
    FROM dbo.exercises
    WHERE exerciseid = p_exerciseid
      AND (createdbyuserid IS NULL OR createdbyuserid = p_userid);

    IF v_exercisename IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_exerciseid, 'That exercise no longer exists.');
        RETURN;
    END IF;

    SELECT d.title INTO v_daytitle FROM dbo.splitdays d WHERE d.splitdayid = p_splitdayid;

    IF v_daytitle IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_splitdayid, 'That training day no longer exists.');
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM dbo.splitdays d
                   INNER JOIN dbo.workoutsplits s ON s.splitid = d.splitid
                   WHERE d.splitdayid = p_splitdayid
                     AND s.owneruserid = p_userid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_splitdayid, 'You can only edit splits you built yourself.');
        RETURN;
    END IF;

    IF p_targetsets < 1 OR p_targetsets > 20 THEN
        RETURN NEXT dbo.outcome_cursor(3, p_splitdayid, 'Target sets must be between 1 and 20.');
        RETURN;
    END IF;

    IF p_targetrepslow < 1 OR p_targetrepshigh < 1 OR p_targetrepslow > p_targetrepshigh OR p_targetrepshigh > 100 THEN
        RETURN NEXT dbo.outcome_cursor(3, p_splitdayid,
            'Rep range must be 1-100 with the low end no higher than the high end.');
        RETURN;
    END IF;

    IF v_splitdayexerciseid IS NULL THEN
        v_splitdayexerciseid := gen_random_uuid();

        INSERT INTO dbo.splitdayexercises
            (splitdayexerciseid, splitdayid, exerciseid, sortorder, targetsets, targetrepslow, targetrepshigh)
        VALUES
            (v_splitdayexerciseid, p_splitdayid, p_exerciseid, p_sortorder, p_targetsets, p_targetrepslow, p_targetrepshigh);
    ELSE
        UPDATE dbo.splitdayexercises
        SET exerciseid = p_exerciseid,
            sortorder = p_sortorder,
            targetsets = p_targetsets,
            targetrepslow = p_targetrepslow,
            targetrepshigh = p_targetrepshigh
        WHERE splitdayexerciseid = v_splitdayexerciseid
          AND splitdayid = p_splitdayid;

        IF NOT FOUND THEN
            RETURN NEXT dbo.outcome_cursor(1, v_splitdayexerciseid, 'That row no longer exists on this day.');
            RETURN;
        END IF;
    END IF;

    RETURN NEXT dbo.outcome_cursor(0, v_splitdayexerciseid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_usersplitdayexercise_delete(
    p_splitdayexerciseid uuid,
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1
                   FROM dbo.splitdayexercises sde
                   INNER JOIN dbo.exercises e ON e.exerciseid = sde.exerciseid
                   WHERE sde.splitdayexerciseid = p_splitdayexerciseid) THEN
        RETURN NEXT dbo.outcome_cursor(1, p_splitdayexerciseid, 'That row no longer exists.');
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM dbo.splitdayexercises sde
                   INNER JOIN dbo.splitdays d ON d.splitdayid = sde.splitdayid
                   INNER JOIN dbo.workoutsplits s ON s.splitid = d.splitid
                   WHERE sde.splitdayexerciseid = p_splitdayexerciseid
                     AND s.owneruserid = p_userid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_splitdayexerciseid, 'You can only edit splits you built yourself.');
        RETURN;
    END IF;

    DELETE FROM dbo.splitdayexercises WHERE splitdayexerciseid = p_splitdayexerciseid;

    RETURN NEXT dbo.outcome_cursor(0, p_splitdayexerciseid, NULL);
END $$;

-- Marks an AI-generated split as permanent: once aikeptatutc is set,
-- Silen.Tools.WeeklyPlanGeneration's next run treats this row as off-limits
-- for overwrite-in-place and creates a fresh one instead. A no-op (not an
-- error) if the split isn't AI-generated or is already kept, so the endpoint
-- stays idempotent.
CREATE OR REPLACE FUNCTION dbo.usp_usersplit_keep(
    p_splitid uuid,
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.workoutsplits WHERE splitid = p_splitid) THEN
        RETURN NEXT dbo.outcome_cursor(1, p_splitid, 'That split no longer exists.');
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM dbo.workoutsplits WHERE splitid = p_splitid AND owneruserid = p_userid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_splitid, 'You can only keep splits you built yourself.');
        RETURN;
    END IF;

    UPDATE dbo.workoutsplits
    SET aikeptatutc = dbo.sysutcdatetime()
    WHERE splitid = p_splitid
      AND isaigenerated
      AND aikeptatutc IS NULL;

    RETURN NEXT dbo.outcome_cursor(0, p_splitid, NULL);
END $$;

-- Copies a split the user owns - header, days and each day's exercises - into
-- a brand-new private split owned by the same user, named "<name> (copy)".
-- The copy is a plain hand-built split: never AI-generated, never kept, never
-- a system default. Tier rules (Free can't duplicate, MaxActiveSplits) are
-- checked by SplitService before this runs.
CREATE OR REPLACE FUNCTION dbo.usp_usersplit_duplicate(
    p_splitid uuid,
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_newsplitid uuid := gen_random_uuid();
    v_newdayid uuid;
    d record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.workoutsplits WHERE splitid = p_splitid) THEN
        RETURN NEXT dbo.outcome_cursor(1, p_splitid, 'That split no longer exists.');
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM dbo.workoutsplits WHERE splitid = p_splitid AND owneruserid = p_userid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_splitid, 'You can only duplicate splits you built yourself.');
        RETURN;
    END IF;

    INSERT INTO dbo.workoutsplits
        (splitid, name, category, level, durationdays, description, heroimageurl, recommendedgoal,
         issystemdefault, sortorder, visibility, owneruserid, isaigenerated,
         daysperweek, programdurationweeks, minsessionminutes, maxsessionminutes,
         equipmentrequired, targetgender, workouttypelabel)
    SELECT v_newsplitid, left(s.name, 143) || ' (copy)', s.category, s.level, s.durationdays,
           s.description, s.heroimageurl, s.recommendedgoal,
           false, s.sortorder, 'Private', p_userid, false,
           s.daysperweek, s.programdurationweeks, s.minsessionminutes, s.maxsessionminutes,
           s.equipmentrequired, s.targetgender, s.workouttypelabel
    FROM dbo.workoutsplits s
    WHERE s.splitid = p_splitid;

    FOR d IN SELECT * FROM dbo.splitdays WHERE splitid = p_splitid LOOP
        v_newdayid := gen_random_uuid();

        INSERT INTO dbo.splitdays (splitdayid, splitid, dayindex, title, focuslabel, estimatedminutes, isrestday)
        VALUES (v_newdayid, v_newsplitid, d.dayindex, d.title, d.focuslabel, d.estimatedminutes, d.isrestday);

        INSERT INTO dbo.splitdayexercises
            (splitdayexerciseid, splitdayid, exerciseid, sortorder, targetsets, targetrepslow, targetrepshigh)
        SELECT gen_random_uuid(), v_newdayid, e.exerciseid, e.sortorder, e.targetsets, e.targetrepslow, e.targetrepshigh
        FROM dbo.splitdayexercises e
        WHERE e.splitdayid = d.splitdayid;
    END LOOP;

    RETURN NEXT dbo.outcome_cursor(0, v_newsplitid, NULL);
END $$;

-- Copies one day of a split the user owns, with its exercises, into the slot
-- right after it. Later days move down one to make room; a split never goes
-- past 14 days. The split's length grows with it if the days now run past it.
CREATE OR REPLACE FUNCTION dbo.usp_usersplitday_duplicate(
    p_splitdayid uuid,
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_day dbo.splitdays%ROWTYPE;
    v_newdayid uuid := gen_random_uuid();
    v_target smallint;
    v_lastindex smallint;
BEGIN
    SELECT * INTO v_day FROM dbo.splitdays WHERE splitdayid = p_splitdayid;

    IF v_day.splitdayid IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_splitdayid, 'That day no longer exists.');
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM dbo.workoutsplits WHERE splitid = v_day.splitid AND owneruserid = p_userid) THEN
        RETURN NEXT dbo.outcome_cursor(2, p_splitdayid, 'You can only edit splits you built yourself.');
        RETURN;
    END IF;

    v_target := v_day.dayindex + 1;

    IF EXISTS (SELECT 1 FROM dbo.splitdays WHERE splitid = v_day.splitid AND dayindex = v_target) THEN
        SELECT max(dayindex) INTO v_lastindex FROM dbo.splitdays WHERE splitid = v_day.splitid;
        IF v_lastindex >= 14 THEN
            RETURN NEXT dbo.outcome_cursor(3, p_splitdayid, 'A split can have at most 14 days.');
            RETURN;
        END IF;

        -- uq_splitdays_splitdayindex is checked row by row, so a plain +1 would
        -- collide with the next day mid-update: park the days out of range first.
        UPDATE dbo.splitdays SET dayindex = dayindex + 100
        WHERE splitid = v_day.splitid AND dayindex > v_day.dayindex;
        UPDATE dbo.splitdays SET dayindex = dayindex - 99
        WHERE splitid = v_day.splitid AND dayindex > 100;
    ELSIF v_target > 14 THEN
        RETURN NEXT dbo.outcome_cursor(3, p_splitdayid, 'A split can have at most 14 days.');
        RETURN;
    END IF;

    INSERT INTO dbo.splitdays (splitdayid, splitid, dayindex, title, focuslabel, estimatedminutes, isrestday)
    VALUES (v_newdayid, v_day.splitid, v_target, v_day.title, v_day.focuslabel, v_day.estimatedminutes, v_day.isrestday);

    INSERT INTO dbo.splitdayexercises
        (splitdayexerciseid, splitdayid, exerciseid, sortorder, targetsets, targetrepslow, targetrepshigh)
    SELECT gen_random_uuid(), v_newdayid, e.exerciseid, e.sortorder, e.targetsets, e.targetrepslow, e.targetrepshigh
    FROM dbo.splitdayexercises e
    WHERE e.splitdayid = p_splitdayid;

    UPDATE dbo.workoutsplits
    SET durationdays = (SELECT max(dayindex) FROM dbo.splitdays WHERE splitid = v_day.splitid)
    WHERE splitid = v_day.splitid
      AND durationdays < (SELECT max(dayindex) FROM dbo.splitdays WHERE splitid = v_day.splitid);

    RETURN NEXT dbo.outcome_cursor(0, v_newdayid, NULL);
END $$;
