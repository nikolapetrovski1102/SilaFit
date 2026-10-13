-- Admin access to the split library: workoutsplits -> splitdays -> splitdayexercises.
--
-- Reads include the counts the console needs to warn before a destructive edit
-- (how many users have a split active, how many exercises a day carries). Writes
-- audit themselves in the same transaction and return Outcome / EntityId / Detail,
-- exactly like AdminContent.sql. Permission checks live in the API, not here.
--
-- Enum columns (category, level, recommendedgoal) keep their CHECK constraints as
-- the source of truth.

-- p_includeall = true is an operator with content.splits.manage_all: they see
-- the whole library. Otherwise a trainer sees only what they own, plus the
-- shipped system splits (read-only reference material they can copy from).
CREATE OR REPLACE FUNCTION dbo.usp_admin_splits_getall(
    p_vieweradminuserid uuid DEFAULT NULL,
    p_includeall boolean DEFAULT true
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
           s.recommendedgoal,
           s.issystemdefault,
           s.visibility,
           s.owneradminuserid,
           owner_admin.username AS ownerusername,
           s.sortorder,
           s.createdatutc,
           (SELECT COUNT(*)::int FROM dbo.splitdays d WHERE d.splitid = s.splitid) AS daycount,
           (SELECT COUNT(*)::int
            FROM dbo.splitdayexercises sde
            INNER JOIN dbo.splitdays d ON d.splitdayid = sde.splitdayid
            WHERE d.splitid = s.splitid) AS exercisecount,
           (SELECT COUNT(*)::int FROM dbo.useractivesplits a WHERE a.splitid = s.splitid) AS activeusercount,
           (SELECT COUNT(*)::int FROM dbo.splitassignments asg WHERE asg.splitid = s.splitid) AS assignedusercount
    FROM dbo.workoutsplits s
    LEFT JOIN dbo.adminusers owner_admin ON owner_admin.adminuserid = s.owneradminuserid
    -- A user-built split (owneruserid set) never surfaces in the console: it is
    -- that user's own content, managed only through the app's UserSplits
    -- endpoints, never through the admin side.
    WHERE s.owneruserid IS NULL
      AND (p_includeall
           OR s.owneradminuserid = p_vieweradminuserid
           OR s.issystemdefault)
    ORDER BY s.sortorder, s.name;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_split_upsert(
    p_splitid uuid DEFAULT NULL,
    p_name text DEFAULT NULL,
    p_category text DEFAULT NULL,
    p_level text DEFAULT NULL,
    p_durationdays smallint DEFAULT NULL,
    p_description text DEFAULT NULL,
    p_heroimageurl text DEFAULT NULL,
    p_recommendedgoal text DEFAULT NULL,
    p_sortorder integer DEFAULT 0,
    p_visibility text DEFAULT 'Public',
    p_actorcanmanageall boolean DEFAULT true,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_splitid uuid := p_splitid;
    v_name text := btrim(p_name);
    v_category text := btrim(p_category);
    v_level text := btrim(p_level);
    v_description text := NULLIF(btrim(p_description), '');
    v_heroimageurl text := NULLIF(btrim(p_heroimageurl), '');
    v_recommendedgoal text := NULLIF(btrim(p_recommendedgoal), '');
    v_visibility text := btrim(p_visibility);
    v_action text;
    v_existingowneradminuserid uuid;
    v_existingowneruserid uuid;
BEGIN
    IF v_name IS NULL OR v_name = '' THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A split name is required.');
        RETURN;
    END IF;

    IF p_durationdays < 1 OR p_durationdays > 14 THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A split lasts between 1 and 14 days.');
        RETURN;
    END IF;

    IF v_visibility IS NULL OR v_visibility COLLATE ci NOT IN ('Private', 'Public', 'Shared') THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'Visibility must be Private, Public or Shared.');
        RETURN;
    END IF;

    IF v_splitid IS NULL THEN
        v_splitid := gen_random_uuid();
        v_action := 'Create';

        INSERT INTO dbo.workoutsplits
            (splitid, name, category, level, durationdays, description, heroimageurl, recommendedgoal,
             issystemdefault, sortorder, visibility, owneradminuserid)
        VALUES
            (v_splitid, v_name, v_category, v_level, p_durationdays, v_description, v_heroimageurl, v_recommendedgoal,
             false, p_sortorder, v_visibility, p_actoradminuserid);
    ELSE
        v_action := 'Update';

        SELECT owneradminuserid, owneruserid
        INTO v_existingowneradminuserid, v_existingowneruserid
        FROM dbo.workoutsplits
        WHERE splitid = v_splitid;

        IF NOT FOUND THEN
            RETURN NEXT dbo.outcome_cursor(1, v_splitid, 'That split no longer exists.');
            RETURN;
        END IF;

        -- A split an app user built themselves is never editable from the
        -- console, regardless of manage_all - it isn't trainer/admin content at
        -- all. usp_admin_splits_getall already excludes these from the list;
        -- this is defense in depth for a direct call.
        IF v_existingowneruserid IS NOT NULL THEN
            RETURN NEXT dbo.outcome_cursor(2, v_splitid, 'This split was built by an app user and cannot be edited here.');
            RETURN;
        END IF;

        -- Ownership is enforced here rather than in the API so it holds inside
        -- the same transaction as the write. A trainer may only change a split
        -- whose owner is them; manage_all operators (and tooling, which passes
        -- the default true) may change any. System/legacy splits have a NULL
        -- owner, so they are manage_all-only too.
        IF NOT p_actorcanmanageall
           AND v_existingowneradminuserid IS DISTINCT FROM p_actoradminuserid THEN
            RETURN NEXT dbo.outcome_cursor(2, v_splitid, 'This split belongs to another trainer.');
            RETURN;
        END IF;

        UPDATE dbo.workoutsplits
        SET name = v_name,
            category = v_category,
            level = v_level,
            durationdays = p_durationdays,
            description = v_description,
            heroimageurl = v_heroimageurl,
            recommendedgoal = v_recommendedgoal,
            sortorder = p_sortorder,
            visibility = v_visibility
        WHERE splitid = v_splitid;
    END IF;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, v_action, 'WorkoutSplit', v_splitid::text,
            v_action || ' split ''' || v_name || ''' (' || v_category || '/' || v_level || ', '
            || p_durationdays::text || ' days, ' || v_visibility || ')', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_splitid, NULL);
END $$;

-- Deleting a split is the one delete in the console that removes a tree (days and
-- their exercise rows). Blocked outright while any user has the split active,
-- because their next workout would otherwise fail.
CREATE OR REPLACE FUNCTION dbo.usp_admin_split_delete(
    p_splitid uuid,
    p_actorcanmanageall boolean DEFAULT true,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_name text;
    v_owneradminuserid uuid;
    v_owneruserid uuid;
    v_activeusercount integer;
    v_daycount integer;
    v_exercisecount integer;
BEGIN
    SELECT name, owneradminuserid, owneruserid
    INTO v_name, v_owneradminuserid, v_owneruserid
    FROM dbo.workoutsplits
    WHERE splitid = p_splitid;

    IF v_name IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_splitid, 'That split no longer exists.');
        RETURN;
    END IF;

    -- Same "not console content at all" guard as the upsert - see there.
    IF v_owneruserid IS NOT NULL THEN
        RETURN NEXT dbo.outcome_cursor(2, p_splitid, 'This split was built by an app user and cannot be deleted here.');
        RETURN;
    END IF;

    -- Same ownership rule as the upsert: a trainer may only delete their own.
    IF NOT p_actorcanmanageall
       AND v_owneradminuserid IS DISTINCT FROM p_actoradminuserid THEN
        RETURN NEXT dbo.outcome_cursor(2, p_splitid, 'This split belongs to another trainer.');
        RETURN;
    END IF;

    SELECT COUNT(*) INTO v_activeusercount FROM dbo.useractivesplits WHERE splitid = p_splitid;

    IF v_activeusercount > 0 THEN
        RETURN NEXT dbo.outcome_cursor(2, p_splitid,
            '''' || v_name || ''' is active for ' || v_activeusercount::text || ' user(s) and cannot be deleted.');
        RETURN;
    END IF;

    SELECT COUNT(*) INTO v_daycount FROM dbo.splitdays d WHERE d.splitid = p_splitid;
    SELECT COUNT(*) INTO v_exercisecount
    FROM dbo.splitdayexercises sde
    INNER JOIN dbo.splitdays d ON d.splitdayid = sde.splitdayid
    WHERE d.splitid = p_splitid;

    DELETE FROM dbo.splitdayexercises
    WHERE splitdayid IN (SELECT splitdayid FROM dbo.splitdays WHERE splitid = p_splitid);

    DELETE FROM dbo.splitdays WHERE splitid = p_splitid;
    DELETE FROM dbo.workoutsplits WHERE splitid = p_splitid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Delete', 'WorkoutSplit', p_splitid::text,
            'Deleted split ''' || v_name || ''' with ' || v_daycount::text || ' day(s) and '
            || v_exercisecount::text || ' exercise row(s)', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_splitid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_splitdays_getforsplit(
    p_splitid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT d.splitdayid,
           d.splitid,
           d.dayindex,
           d.title,
           d.focuslabel,
           d.estimatedminutes,
           d.isrestday,
           (SELECT COUNT(*)::int FROM dbo.splitdayexercises sde WHERE sde.splitdayid = d.splitdayid) AS exercisecount
    FROM dbo.splitdays d
    WHERE d.splitid = p_splitid
    ORDER BY d.dayindex;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_splitday_upsert(
    p_splitdayid uuid DEFAULT NULL,
    p_splitid uuid DEFAULT NULL,
    p_dayindex smallint DEFAULT NULL,
    p_title text DEFAULT NULL,
    p_focuslabel text DEFAULT NULL,
    p_estimatedminutes smallint DEFAULT 45,
    p_isrestday boolean DEFAULT false,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_splitdayid uuid := p_splitdayid;
    v_title text := btrim(p_title);
    v_focuslabel text := NULLIF(btrim(p_focuslabel), '');
    v_splitname text;
    v_action text;
BEGIN
    SELECT name INTO v_splitname FROM dbo.workoutsplits WHERE splitid = p_splitid;

    IF v_splitname IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_splitid, 'That split no longer exists.');
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

    -- uq_splitdays_splitdayindex is the real guard; checked here to return a
    -- sentence instead of a duplicate-key error.
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
        v_action := 'Create';

        INSERT INTO dbo.splitdays (splitdayid, splitid, dayindex, title, focuslabel, estimatedminutes, isrestday)
        VALUES (v_splitdayid, p_splitid, p_dayindex, v_title, v_focuslabel, p_estimatedminutes, p_isrestday);
    ELSE
        v_action := 'Update';

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

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, v_action, 'SplitDay', v_splitdayid::text,
            v_action || ' day ' || p_dayindex::text || ' (' || v_title || ') on split ''' || v_splitname || '''', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_splitdayid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_splitday_delete(
    p_splitdayid uuid,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_title text;
    v_dayindex smallint;
    v_splitname text;
    v_exercisecount integer;
BEGIN
    SELECT d.title, d.dayindex, s.name
    INTO v_title, v_dayindex, v_splitname
    FROM dbo.splitdays d
    INNER JOIN dbo.workoutsplits s ON s.splitid = d.splitid
    WHERE d.splitdayid = p_splitdayid;

    IF v_title IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_splitdayid, 'That day no longer exists.');
        RETURN;
    END IF;

    SELECT COUNT(*) INTO v_exercisecount FROM dbo.splitdayexercises WHERE splitdayid = p_splitdayid;

    -- No FK cascade here, so the exercise rows go first.
    DELETE FROM dbo.splitdayexercises WHERE splitdayid = p_splitdayid;
    DELETE FROM dbo.splitdays WHERE splitdayid = p_splitdayid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Delete', 'SplitDay', p_splitdayid::text,
            'Deleted day ' || v_dayindex::text || ' (' || v_title || ') from split ''' || v_splitname
            || ''' with ' || v_exercisecount::text || ' exercise row(s)', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_splitdayid, NULL);
END $$;

-- Every prescription row of a split, with the exercise name, so the console can
-- render a day without a second lookup per exercise.
CREATE OR REPLACE FUNCTION dbo.usp_admin_splitdayexercises_getforsplit(
    p_splitid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT sde.splitdayexerciseid,
           sde.splitdayid,
           d.dayindex,
           sde.exerciseid,
           e.name AS exercisename,
           e.musclegroup,
           sde.sortorder,
           sde.targetsets,
           sde.targetrepslow,
           sde.targetrepshigh
    FROM dbo.splitdayexercises sde
    INNER JOIN dbo.splitdays d ON d.splitdayid = sde.splitdayid
    INNER JOIN dbo.exercises e ON e.exerciseid = sde.exerciseid
    WHERE d.splitid = p_splitid
    ORDER BY d.dayindex, sde.sortorder;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_splitdayexercise_upsert(
    p_splitdayexerciseid uuid DEFAULT NULL,
    p_splitdayid uuid DEFAULT NULL,
    p_exerciseid uuid DEFAULT NULL,
    p_sortorder smallint DEFAULT 0,
    p_targetsets smallint DEFAULT NULL,
    p_targetrepslow smallint DEFAULT NULL,
    p_targetrepshigh smallint DEFAULT NULL,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_splitdayexerciseid uuid := p_splitdayexerciseid;
    v_exercisename text;
    v_daytitle text;
    v_action text;
BEGIN
    SELECT name INTO v_exercisename FROM dbo.exercises WHERE exerciseid = p_exerciseid;

    IF v_exercisename IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_exerciseid, 'That exercise no longer exists.');
        RETURN;
    END IF;

    SELECT d.title INTO v_daytitle FROM dbo.splitdays d WHERE d.splitdayid = p_splitdayid;

    IF v_daytitle IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_splitdayid, 'That training day no longer exists.');
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
        v_action := 'Create';

        INSERT INTO dbo.splitdayexercises
            (splitdayexerciseid, splitdayid, exerciseid, sortorder, targetsets, targetrepslow, targetrepshigh)
        VALUES
            (v_splitdayexerciseid, p_splitdayid, p_exerciseid, p_sortorder, p_targetsets, p_targetrepslow, p_targetrepshigh);
    ELSE
        v_action := 'Update';

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

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, v_action, 'SplitDayExercise', v_splitdayexerciseid::text,
            v_action || ' ''' || v_exercisename || ''' on ''' || v_daytitle || ''' ('
            || p_targetsets::text || 'x' || p_targetrepslow::text || '-'
            || p_targetrepshigh::text || ')', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_splitdayexerciseid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_splitdayexercise_delete(
    p_splitdayexerciseid uuid,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_exercisename text;
    v_daytitle text;
BEGIN
    SELECT e.name, d.title INTO v_exercisename, v_daytitle
    FROM dbo.splitdayexercises sde
    INNER JOIN dbo.exercises e ON e.exerciseid = sde.exerciseid
    INNER JOIN dbo.splitdays d ON d.splitdayid = sde.splitdayid
    WHERE sde.splitdayexerciseid = p_splitdayexerciseid;

    IF v_exercisename IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_splitdayexerciseid, 'That row no longer exists.');
        RETURN;
    END IF;

    DELETE FROM dbo.splitdayexercises WHERE splitdayexerciseid = p_splitdayexerciseid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Delete', 'SplitDayExercise', p_splitdayexerciseid::text,
            'Removed ''' || v_exercisename || ''' from ''' || v_daytitle || '''', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_splitdayexerciseid, NULL);
END $$;

-- =============================================================================
-- Assignment: handing a split to specific paying clients.
--
-- One splitassignments row means "this user may see this split", which is what
-- the app-side library filter reads. Assignment therefore works for any
-- visibility: a Private split flips to Shared the moment it is assigned (a
-- grant to a person is, by definition, sharing it with that person), while a
-- Public split stays public and simply gains another client.
--
-- p_actorcanmanageall mirrors the upsert/delete ownership rule: a trainer
-- assigns only their own splits; manage_all operators assign anything.
-- =============================================================================

CREATE OR REPLACE FUNCTION dbo.usp_admin_splitassignments_getforsplit(
    p_splitid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT a.splitid,
           a.userid,
           u.displayname,
           u.email,
           u.accounttier,
           a.assignedatutc,
           assigned_by.username AS assignedbyusername,
           active.userid IS NOT NULL AS isactive,
           subplan.code AS activeplancode,
           sub.billingcycle,
           sub.status AS subscriptionstatus
    FROM dbo.splitassignments a
    INNER JOIN dbo.users u ON u.userid = a.userid
    LEFT JOIN dbo.adminusers assigned_by ON assigned_by.adminuserid = a.assignedbyadminuserid
    LEFT JOIN dbo.useractivesplits active ON active.userid = a.userid AND active.splitid = a.splitid
    -- usersubscriptions has userid as its primary key, so this is at most one row.
    LEFT JOIN dbo.usersubscriptions sub ON sub.userid = a.userid
    LEFT JOIN dbo.subscriptionplans subplan ON subplan.planid = sub.planid
    WHERE a.splitid = p_splitid
    ORDER BY u.displayname NULLS FIRST, u.email NULLS FIRST;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_splitassignment_assign(
    p_splitid uuid,
    p_userid uuid,
    p_setactive boolean DEFAULT false,
    p_actorcanmanageall boolean DEFAULT true,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_splitname text;
    v_owneradminuserid uuid;
    v_visibility text;
    v_clientlabel text;
BEGIN
    SELECT name, owneradminuserid, visibility
    INTO v_splitname, v_owneradminuserid, v_visibility
    FROM dbo.workoutsplits
    WHERE splitid = p_splitid;

    IF v_splitname IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_splitid, 'That split no longer exists.');
        RETURN;
    END IF;

    IF NOT p_actorcanmanageall
       AND v_owneradminuserid IS DISTINCT FROM p_actoradminuserid THEN
        RETURN NEXT dbo.outcome_cursor(2, p_splitid, 'Only the trainer who owns this split can assign it.');
        RETURN;
    END IF;

    SELECT COALESCE(NULLIF(displayname, ''), NULLIF(email, ''), userid::text) INTO v_clientlabel
    FROM dbo.users
    WHERE userid = p_userid;

    IF v_clientlabel IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_userid, 'That user no longer exists.');
        RETURN;
    END IF;

    -- Idempotent: re-assigning an already-assigned client is not an error; it
    -- only refreshes who did it and, when asked, sets it active again.
    INSERT INTO dbo.splitassignments (splitid, userid, assignedbyadminuserid)
    VALUES (p_splitid, p_userid, p_actoradminuserid)
    ON CONFLICT (splitid, userid) DO UPDATE
    SET assignedbyadminuserid = EXCLUDED.assignedbyadminuserid,
        assignedatutc = dbo.sysutcdatetime();

    -- A grant to a named person makes a private split shared (with that person).
    IF v_visibility = 'Private' THEN
        UPDATE dbo.workoutsplits SET visibility = 'Shared' WHERE splitid = p_splitid;
        v_visibility := 'Shared';
    END IF;

    -- A trainer's pick is deliberate, never the recommender's, so it also
    -- clears any isautoassigned flag left by the split it replaces.
    IF p_setactive THEN
        INSERT INTO dbo.useractivesplits (userid, splitid, activatedatutc, isautoassigned)
        VALUES (p_userid, p_splitid, dbo.sysutcdatetime(), false)
        ON CONFLICT (userid) DO UPDATE
        SET splitid = EXCLUDED.splitid, activatedatutc = EXCLUDED.activatedatutc, isautoassigned = false;
    END IF;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Assign', 'SplitAssignment', p_userid::text,
            'Assigned split ''' || v_splitname || ''' (' || v_visibility || ') to ' || v_clientlabel
            || CASE WHEN p_setactive THEN ' as their active split' ELSE '' END,
            p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_splitid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_splitassignment_remove(
    p_splitid uuid,
    p_userid uuid,
    p_actorcanmanageall boolean DEFAULT true,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_splitname text;
    v_owneradminuserid uuid;
    v_wasactive boolean;
    v_clientlabel text;
BEGIN
    SELECT name, owneradminuserid INTO v_splitname, v_owneradminuserid
    FROM dbo.workoutsplits
    WHERE splitid = p_splitid;

    IF v_splitname IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_splitid, 'That split no longer exists.');
        RETURN;
    END IF;

    IF NOT p_actorcanmanageall
       AND v_owneradminuserid IS DISTINCT FROM p_actoradminuserid THEN
        RETURN NEXT dbo.outcome_cursor(2, p_splitid, 'Only the trainer who owns this split can unassign it.');
        RETURN;
    END IF;

    v_wasactive := EXISTS (SELECT 1 FROM dbo.useractivesplits WHERE userid = p_userid AND splitid = p_splitid);

    DELETE FROM dbo.splitassignments WHERE splitid = p_splitid AND userid = p_userid;

    IF NOT FOUND THEN
        RETURN NEXT dbo.outcome_cursor(1, p_userid, 'That client was not assigned this split.');
        RETURN;
    END IF;

    -- If it was their active program, clear it: the user can no longer see the
    -- split, so leaving it active would strand their Today screen on a workout
    -- they are no longer allowed to read.
    IF v_wasactive THEN
        DELETE FROM dbo.useractivesplits WHERE userid = p_userid AND splitid = p_splitid;
    END IF;

    SELECT COALESCE(NULLIF(displayname, ''), NULLIF(email, ''), userid::text) INTO v_clientlabel
    FROM dbo.users WHERE userid = p_userid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Unassign', 'SplitAssignment', p_userid::text,
            'Unassigned split ''' || v_splitname || ''' from ' || COALESCE(v_clientlabel, p_userid::text)
            || CASE WHEN v_wasactive THEN ' (and cleared it as their active split)' ELSE '' END,
            p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_splitid, NULL);
END $$;
