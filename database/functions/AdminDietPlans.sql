-- Admin access to the diet-plan library: nutritionplans -> dietplandays -> dietplanmeals.
-- A 1:1 structural clone of AdminSplits.sql for the meal-planning equivalent -
-- same Outcome/EntityId/Detail write shape, same trainer-owns-their-own /
-- manage_all-owns-everything rule, same "own content only, never the app
-- user's own content" exclusion. Permission checks live in the API, not here.

-- p_includeall = true is an operator with content.diet_plans.manage_all: they
-- see the whole library. Otherwise a trainer sees only what they own, plus the
-- shipped system plans (read-only reference material they can copy from).
CREATE OR REPLACE FUNCTION dbo.usp_admin_dietplans_getall(
    p_vieweradminuserid uuid DEFAULT NULL,
    p_includeall boolean DEFAULT true
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
           dp.visibility,
           dp.owneradminuserid,
           owner_admin.username AS ownerusername,
           dp.sortorder,
           dp.createdatutc,
           (SELECT COUNT(*)::int FROM dbo.dietplandays d WHERE d.dietplanid = dp.dietplanid) AS daycount,
           (SELECT COUNT(*)::int
            FROM dbo.dietplanmeals m
            INNER JOIN dbo.dietplandays d ON d.dietplandayid = m.dietplandayid
            WHERE d.dietplanid = dp.dietplanid) AS mealcount,
           (SELECT COUNT(*)::int FROM dbo.useractivedietplans a WHERE a.dietplanid = dp.dietplanid) AS activeusercount,
           (SELECT COUNT(*)::int FROM dbo.dietplanassignments asg WHERE asg.dietplanid = dp.dietplanid) AS assignedusercount
    FROM dbo.nutritionplans dp
    LEFT JOIN dbo.adminusers owner_admin ON owner_admin.adminuserid = dp.owneradminuserid
    -- A user-built plan (owneruserid set) never surfaces in the console: it is
    -- that user's own content, managed only through the app's UserDietPlans
    -- endpoints, never through the admin side.
    WHERE dp.owneruserid IS NULL
      AND (p_includeall
           OR dp.owneradminuserid = p_vieweradminuserid
           OR dp.issystemdefault)
    ORDER BY dp.sortorder, dp.name;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_dietplan_upsert(
    p_dietplanid uuid DEFAULT NULL,
    p_name text DEFAULT NULL,
    p_description text DEFAULT NULL,
    p_heroimageurl text DEFAULT NULL,
    p_periodtype text DEFAULT 'Weekly',
    p_durationdays smallint DEFAULT 7,
    p_sortorder integer DEFAULT 0,
    p_visibility text DEFAULT 'Public',
    p_actorcanmanageall boolean DEFAULT true,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_dietplanid uuid := p_dietplanid;
    v_name text := btrim(p_name);
    v_description text := NULLIF(btrim(p_description), '');
    v_heroimageurl text := NULLIF(btrim(p_heroimageurl), '');
    v_periodtype text := btrim(p_periodtype);
    v_visibility text := btrim(p_visibility);
    v_action text;
    v_existingowneradminuserid uuid;
    v_existingowneruserid uuid;
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

    IF v_visibility IS NULL OR v_visibility COLLATE ci NOT IN ('Private', 'Public', 'Shared') THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'Visibility must be Private, Public or Shared.');
        RETURN;
    END IF;

    IF v_dietplanid IS NULL THEN
        v_dietplanid := gen_random_uuid();
        v_action := 'Create';

        INSERT INTO dbo.nutritionplans
            (dietplanid, name, description, heroimageurl, periodtype, durationdays,
             issystemdefault, sortorder, visibility, owneradminuserid)
        VALUES
            (v_dietplanid, v_name, v_description, v_heroimageurl, v_periodtype, p_durationdays,
             false, p_sortorder, v_visibility, p_actoradminuserid);
    ELSE
        v_action := 'Update';

        SELECT owneradminuserid, owneruserid
        INTO v_existingowneradminuserid, v_existingowneruserid
        FROM dbo.nutritionplans
        WHERE dietplanid = v_dietplanid;

        IF NOT FOUND THEN
            RETURN NEXT dbo.outcome_cursor(1, v_dietplanid, 'That plan no longer exists.');
            RETURN;
        END IF;

        -- A plan an app user built themselves is never editable from the
        -- console, regardless of manage_all - see usp_admin_split_upsert's
        -- matching guard for the same rule on the workout side.
        IF v_existingowneruserid IS NOT NULL THEN
            RETURN NEXT dbo.outcome_cursor(2, v_dietplanid, 'This plan was built by an app user and cannot be edited here.');
            RETURN;
        END IF;

        IF NOT p_actorcanmanageall
           AND v_existingowneradminuserid IS DISTINCT FROM p_actoradminuserid THEN
            RETURN NEXT dbo.outcome_cursor(2, v_dietplanid, 'This plan belongs to another trainer.');
            RETURN;
        END IF;

        UPDATE dbo.nutritionplans
        SET name = v_name,
            description = v_description,
            heroimageurl = v_heroimageurl,
            periodtype = v_periodtype,
            durationdays = p_durationdays,
            sortorder = p_sortorder,
            visibility = v_visibility
        WHERE dietplanid = v_dietplanid;
    END IF;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, v_action, 'DietPlan', v_dietplanid::text,
            v_action || ' diet plan ''' || v_name || ''' (' || v_periodtype || ', '
            || p_durationdays::text || ' days, ' || v_visibility || ')', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_dietplanid, NULL);
END $$;

-- Deleting a plan removes its tree (days and their meal rows). Blocked
-- outright while any user has the plan active, same guard as
-- usp_admin_split_delete.
CREATE OR REPLACE FUNCTION dbo.usp_admin_dietplan_delete(
    p_dietplanid uuid,
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
    v_mealcount integer;
BEGIN
    SELECT name, owneradminuserid, owneruserid
    INTO v_name, v_owneradminuserid, v_owneruserid
    FROM dbo.nutritionplans
    WHERE dietplanid = p_dietplanid;

    IF v_name IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_dietplanid, 'That plan no longer exists.');
        RETURN;
    END IF;

    IF v_owneruserid IS NOT NULL THEN
        RETURN NEXT dbo.outcome_cursor(2, p_dietplanid, 'This plan was built by an app user and cannot be deleted here.');
        RETURN;
    END IF;

    IF NOT p_actorcanmanageall
       AND v_owneradminuserid IS DISTINCT FROM p_actoradminuserid THEN
        RETURN NEXT dbo.outcome_cursor(2, p_dietplanid, 'This plan belongs to another trainer.');
        RETURN;
    END IF;

    SELECT COUNT(*) INTO v_activeusercount FROM dbo.useractivedietplans WHERE dietplanid = p_dietplanid;

    IF v_activeusercount > 0 THEN
        RETURN NEXT dbo.outcome_cursor(2, p_dietplanid,
            '''' || v_name || ''' is active for ' || v_activeusercount::text || ' user(s) and cannot be deleted.');
        RETURN;
    END IF;

    SELECT COUNT(*) INTO v_daycount FROM dbo.dietplandays d WHERE d.dietplanid = p_dietplanid;
    SELECT COUNT(*) INTO v_mealcount
    FROM dbo.dietplanmeals m
    INNER JOIN dbo.dietplandays d ON d.dietplandayid = m.dietplandayid
    WHERE d.dietplanid = p_dietplanid;

    DELETE FROM dbo.dietplanmeals
    WHERE dietplandayid IN (SELECT dietplandayid FROM dbo.dietplandays WHERE dietplanid = p_dietplanid);

    DELETE FROM dbo.dietplandays WHERE dietplanid = p_dietplanid;
    DELETE FROM dbo.nutritionplans WHERE dietplanid = p_dietplanid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Delete', 'DietPlan', p_dietplanid::text,
            'Deleted diet plan ''' || v_name || ''' with ' || v_daycount::text || ' day(s) and '
            || v_mealcount::text || ' meal row(s)', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_dietplanid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_dietplandays_getforplan(
    p_dietplanid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT d.dietplandayid,
           d.dietplanid,
           d.dayindex,
           d.title,
           (SELECT COUNT(*)::int FROM dbo.dietplanmeals m WHERE m.dietplandayid = d.dietplandayid) AS mealcount
    FROM dbo.dietplandays d
    WHERE d.dietplanid = p_dietplanid
    ORDER BY d.dayindex;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_dietplanday_upsert(
    p_dietplandayid uuid DEFAULT NULL,
    p_dietplanid uuid DEFAULT NULL,
    p_dayindex smallint DEFAULT NULL,
    p_title text DEFAULT NULL,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_dietplandayid uuid := p_dietplandayid;
    v_title text := NULLIF(btrim(p_title), '');
    v_planname text;
    v_action text;
BEGIN
    SELECT name INTO v_planname FROM dbo.nutritionplans WHERE dietplanid = p_dietplanid;

    IF v_planname IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_dietplanid, 'That plan no longer exists.');
        RETURN;
    END IF;

    IF p_dayindex < 1 OR p_dayindex > 31 THEN
        RETURN NEXT dbo.outcome_cursor(3, p_dietplanid, 'Day index must be between 1 and 31.');
        RETURN;
    END IF;

    -- uq_dietplandays_plan_dayindex is the real guard; checked here to return
    -- a sentence instead of a duplicate-key error.
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
        v_action := 'Create';

        INSERT INTO dbo.dietplandays (dietplandayid, dietplanid, dayindex, title)
        VALUES (v_dietplandayid, p_dietplanid, p_dayindex, v_title);
    ELSE
        v_action := 'Update';

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

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, v_action, 'DietPlanDay', v_dietplandayid::text,
            v_action || ' day ' || p_dayindex::text || ' on plan ''' || v_planname || '''', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_dietplandayid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_dietplanday_delete(
    p_dietplandayid uuid,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_dayindex smallint;
    v_planname text;
    v_mealcount integer;
BEGIN
    SELECT d.dayindex, p.name INTO v_dayindex, v_planname
    FROM dbo.dietplandays d
    INNER JOIN dbo.nutritionplans p ON p.dietplanid = d.dietplanid
    WHERE d.dietplandayid = p_dietplandayid;

    IF v_planname IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_dietplandayid, 'That day no longer exists.');
        RETURN;
    END IF;

    SELECT COUNT(*) INTO v_mealcount FROM dbo.dietplanmeals WHERE dietplandayid = p_dietplandayid;

    DELETE FROM dbo.dietplanmeals WHERE dietplandayid = p_dietplandayid;
    DELETE FROM dbo.dietplandays WHERE dietplandayid = p_dietplandayid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Delete', 'DietPlanDay', p_dietplandayid::text,
            'Deleted day ' || v_dayindex::text || ' from plan ''' || v_planname
            || ''' with ' || v_mealcount::text || ' meal row(s)', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_dietplandayid, NULL);
END $$;

-- Every meal slot of a plan, with the meal-suggestion's title/macros, so the
-- console can render a day without a second lookup per slot.
CREATE OR REPLACE FUNCTION dbo.usp_admin_dietplanmeals_getforplan(
    p_dietplanid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT m.dietplanmealid,
           m.dietplandayid,
           d.dayindex,
           m.mealtype,
           m.mealsuggestionid,
           ms.title AS mealsuggestiontitle,
           ms.calorieskcal,
           ms.proteing,
           ms.carbsg,
           ms.fatsg,
           m.sortorder
    FROM dbo.dietplanmeals m
    INNER JOIN dbo.dietplandays d ON d.dietplandayid = m.dietplandayid
    INNER JOIN dbo.mealsuggestions ms ON ms.mealsuggestionid = m.mealsuggestionid
    WHERE d.dietplanid = p_dietplanid
    ORDER BY d.dayindex, m.sortorder;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_dietplanmeal_upsert(
    p_dietplanmealid uuid DEFAULT NULL,
    p_dietplandayid uuid DEFAULT NULL,
    p_mealtype text DEFAULT NULL,
    p_mealsuggestionid uuid DEFAULT NULL,
    p_sortorder integer DEFAULT 0,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_dietplanmealid uuid := p_dietplanmealid;
    v_mealtype text := btrim(p_mealtype);
    v_daytitle text;
    v_dayindex smallint;
    v_mealsuggestiontitle text;
    v_action text;
BEGIN
    SELECT COALESCE(title, 'Day ' || dayindex::text), dayindex INTO v_daytitle, v_dayindex
    FROM dbo.dietplandays
    WHERE dietplandayid = p_dietplandayid;

    IF v_dayindex IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_dietplandayid, 'That plan day no longer exists.');
        RETURN;
    END IF;

    IF v_mealtype IS NULL OR v_mealtype COLLATE ci NOT IN ('Breakfast', 'Lunch', 'Dinner', 'Snack') THEN
        RETURN NEXT dbo.outcome_cursor(3, p_dietplandayid, 'Meal type must be Breakfast, Lunch, Dinner or Snack.');
        RETURN;
    END IF;

    SELECT title INTO v_mealsuggestiontitle
    FROM dbo.mealsuggestions
    WHERE mealsuggestionid = p_mealsuggestionid
      AND owneruserid IS NULL;

    IF v_mealsuggestiontitle IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_mealsuggestionid, 'That meal suggestion no longer exists.');
        RETURN;
    END IF;

    IF v_dietplanmealid IS NULL THEN
        v_dietplanmealid := gen_random_uuid();
        v_action := 'Create';

        INSERT INTO dbo.dietplanmeals (dietplanmealid, dietplandayid, mealtype, mealsuggestionid, sortorder)
        VALUES (v_dietplanmealid, p_dietplandayid, v_mealtype, p_mealsuggestionid, p_sortorder);
    ELSE
        v_action := 'Update';

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

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, v_action, 'DietPlanMeal', v_dietplanmealid::text,
            v_action || ' ' || v_mealtype || ' ''' || v_mealsuggestiontitle || ''' on ''' || v_daytitle || '''', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_dietplanmealid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_dietplanmeal_delete(
    p_dietplanmealid uuid,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_mealsuggestiontitle text;
    v_daytitle text;
BEGIN
    SELECT ms.title, COALESCE(d.title, 'Day ' || d.dayindex::text)
    INTO v_mealsuggestiontitle, v_daytitle
    FROM dbo.dietplanmeals m
    INNER JOIN dbo.mealsuggestions ms ON ms.mealsuggestionid = m.mealsuggestionid
    INNER JOIN dbo.dietplandays d ON d.dietplandayid = m.dietplandayid
    WHERE m.dietplanmealid = p_dietplanmealid;

    IF v_mealsuggestiontitle IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_dietplanmealid, 'That meal slot no longer exists.');
        RETURN;
    END IF;

    DELETE FROM dbo.dietplanmeals WHERE dietplanmealid = p_dietplanmealid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Delete', 'DietPlanMeal', p_dietplanmealid::text,
            'Removed ''' || v_mealsuggestiontitle || ''' from ''' || v_daytitle || '''', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_dietplanmealid, NULL);
END $$;

-- =============================================================================
-- Assignment: handing a diet plan to specific paying clients. Mirrors
-- usp_admin_splitassignment_* exactly, including the Private->Shared-on-assign
-- flip and the p_setactive upsert into useractivedietplans.
-- =============================================================================

CREATE OR REPLACE FUNCTION dbo.usp_admin_dietplanassignments_getforplan(
    p_dietplanid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT a.dietplanid,
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
    FROM dbo.dietplanassignments a
    INNER JOIN dbo.users u ON u.userid = a.userid
    LEFT JOIN dbo.adminusers assigned_by ON assigned_by.adminuserid = a.assignedbyadminuserid
    LEFT JOIN dbo.useractivedietplans active ON active.userid = a.userid AND active.dietplanid = a.dietplanid
    LEFT JOIN dbo.usersubscriptions sub ON sub.userid = a.userid
    LEFT JOIN dbo.subscriptionplans subplan ON subplan.planid = sub.planid
    WHERE a.dietplanid = p_dietplanid
    ORDER BY u.displayname NULLS FIRST, u.email NULLS FIRST;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_dietplanassignment_assign(
    p_dietplanid uuid,
    p_userid uuid,
    p_setactive boolean DEFAULT false,
    p_actorcanmanageall boolean DEFAULT true,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_planname text;
    v_owneradminuserid uuid;
    v_visibility text;
    v_clientlabel text;
BEGIN
    SELECT name, owneradminuserid, visibility
    INTO v_planname, v_owneradminuserid, v_visibility
    FROM dbo.nutritionplans
    WHERE dietplanid = p_dietplanid;

    IF v_planname IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_dietplanid, 'That plan no longer exists.');
        RETURN;
    END IF;

    IF NOT p_actorcanmanageall
       AND v_owneradminuserid IS DISTINCT FROM p_actoradminuserid THEN
        RETURN NEXT dbo.outcome_cursor(2, p_dietplanid, 'Only the trainer who owns this plan can assign it.');
        RETURN;
    END IF;

    SELECT COALESCE(NULLIF(displayname, ''), NULLIF(email, ''), userid::text) INTO v_clientlabel
    FROM dbo.users
    WHERE userid = p_userid;

    IF v_clientlabel IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_userid, 'That user no longer exists.');
        RETURN;
    END IF;

    INSERT INTO dbo.dietplanassignments (dietplanid, userid, assignedbyadminuserid)
    VALUES (p_dietplanid, p_userid, p_actoradminuserid)
    ON CONFLICT (dietplanid, userid) DO UPDATE
    SET assignedbyadminuserid = EXCLUDED.assignedbyadminuserid,
        assignedatutc = dbo.sysutcdatetime();

    IF v_visibility = 'Private' THEN
        UPDATE dbo.nutritionplans SET visibility = 'Shared' WHERE dietplanid = p_dietplanid;
        v_visibility := 'Shared';
    END IF;

    IF p_setactive THEN
        INSERT INTO dbo.useractivedietplans (userid, dietplanid, activatedatutc)
        VALUES (p_userid, p_dietplanid, dbo.sysutcdatetime())
        ON CONFLICT (userid) DO UPDATE
        SET dietplanid = EXCLUDED.dietplanid, activatedatutc = EXCLUDED.activatedatutc;
    END IF;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Assign', 'DietPlanAssignment', p_userid::text,
            'Assigned diet plan ''' || v_planname || ''' (' || v_visibility || ') to ' || v_clientlabel
            || CASE WHEN p_setactive THEN ' as their active plan' ELSE '' END,
            p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_dietplanid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_dietplanassignment_remove(
    p_dietplanid uuid,
    p_userid uuid,
    p_actorcanmanageall boolean DEFAULT true,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_planname text;
    v_owneradminuserid uuid;
    v_wasactive boolean;
    v_clientlabel text;
BEGIN
    SELECT name, owneradminuserid INTO v_planname, v_owneradminuserid
    FROM dbo.nutritionplans
    WHERE dietplanid = p_dietplanid;

    IF v_planname IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_dietplanid, 'That plan no longer exists.');
        RETURN;
    END IF;

    IF NOT p_actorcanmanageall
       AND v_owneradminuserid IS DISTINCT FROM p_actoradminuserid THEN
        RETURN NEXT dbo.outcome_cursor(2, p_dietplanid, 'Only the trainer who owns this plan can unassign it.');
        RETURN;
    END IF;

    v_wasactive := EXISTS (SELECT 1 FROM dbo.useractivedietplans WHERE userid = p_userid AND dietplanid = p_dietplanid);

    DELETE FROM dbo.dietplanassignments WHERE dietplanid = p_dietplanid AND userid = p_userid;

    IF NOT FOUND THEN
        RETURN NEXT dbo.outcome_cursor(1, p_userid, 'That client was not assigned this plan.');
        RETURN;
    END IF;

    IF v_wasactive THEN
        DELETE FROM dbo.useractivedietplans WHERE userid = p_userid AND dietplanid = p_dietplanid;
    END IF;

    SELECT COALESCE(NULLIF(displayname, ''), NULLIF(email, ''), userid::text) INTO v_clientlabel
    FROM dbo.users WHERE userid = p_userid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Unassign', 'DietPlanAssignment', p_userid::text,
            'Unassigned diet plan ''' || v_planname || ''' from ' || COALESCE(v_clientlabel, p_userid::text)
            || CASE WHEN v_wasactive THEN ' (and cleared it as their active plan)' ELSE '' END,
            p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_dietplanid, NULL);
END $$;
