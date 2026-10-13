-- Admin (console) access to the reference content the mobile app serves:
-- exercises, meal suggestions, subscription plans and the user list.
--
-- These are deliberately separate from the runtime functions in Exercises.sql /
-- MealPlanning.sql / Plans.sql. The app's functions are shaped for one signed-in
-- user and return only what that user may see; these return whole tables for an
-- operator, with usage counts so the console can warn before a delete.
--
-- Writes audit themselves in the same transaction (dbo.adminauditlog) and return a
-- single Outcome / EntityId / Detail row - see AdminWriteOutcome in Silen.Common.
-- Permission checks are NOT here: the API decides who may call a function, so
-- these stay usable by the provisioning tooling without a role in scope.
--
-- Enum columns (musclegroup, mealtype, category...) are left to their CHECK
-- constraints as the single source of truth; the service layer rejects unknown
-- values with a friendlier message before calling.

-- =============================================================================
-- Exercises
-- =============================================================================

CREATE OR REPLACE FUNCTION dbo.usp_admin_exercises_getall()
RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT e.exerciseid,
           e.name,
           e.musclegroup,
           e.equipmenttype,
           e.iscompound,
           e.demovideourl,
           e.createdatutc,
           (SELECT COUNT(*)::int FROM dbo.splitdayexercises sde WHERE sde.exerciseid = e.exerciseid) AS usagecount
    FROM dbo.exercises e
    -- Users' private exercises (071) aren't catalogue content to curate.
    WHERE e.createdbyuserid IS NULL
    ORDER BY e.musclegroup, e.name;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_exercise_upsert(
    p_exerciseid uuid DEFAULT NULL,
    p_name text DEFAULT NULL,
    p_musclegroup text DEFAULT NULL,
    p_equipmenttype text DEFAULT NULL,
    p_iscompound boolean DEFAULT NULL,
    p_demovideourl text DEFAULT NULL,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_exerciseid uuid := p_exerciseid;
    v_name text := btrim(p_name);
    v_musclegroup text := btrim(p_musclegroup);
    v_equipmenttype text := NULLIF(btrim(p_equipmenttype), '');
    v_demovideourl text := NULLIF(btrim(p_demovideourl), '');
    v_action text;
BEGIN
    IF v_name IS NULL OR v_name = '' THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'An exercise name is required.');
        RETURN;
    END IF;

    IF v_exerciseid IS NULL THEN
        v_exerciseid := gen_random_uuid();
        v_action := 'Create';

        INSERT INTO dbo.exercises (exerciseid, name, musclegroup, equipmenttype, iscompound, demovideourl)
        VALUES (v_exerciseid, v_name, v_musclegroup, v_equipmenttype, p_iscompound, v_demovideourl);
    ELSE
        v_action := 'Update';

        UPDATE dbo.exercises
        SET name = v_name,
            musclegroup = v_musclegroup,
            equipmenttype = v_equipmenttype,
            iscompound = p_iscompound,
            demovideourl = v_demovideourl
        WHERE exerciseid = v_exerciseid;

        IF NOT FOUND THEN
            RETURN NEXT dbo.outcome_cursor(1, v_exerciseid, 'That exercise no longer exists.');
            RETURN;
        END IF;
    END IF;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, v_action, 'Exercise', v_exerciseid::text,
            v_action || ' exercise ''' || v_name || ''' in ' || v_musclegroup, p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_exerciseid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_exercise_delete(
    p_exerciseid uuid,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_name text;
    v_usagecount integer;
BEGIN
    SELECT name INTO v_name FROM dbo.exercises WHERE exerciseid = p_exerciseid;

    IF v_name IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_exerciseid, 'That exercise no longer exists.');
        RETURN;
    END IF;

    -- Checked inside the transaction: a split-day row added a moment ago still
    -- blocks the delete, rather than surfacing as a foreign-key error.
    SELECT COUNT(*) INTO v_usagecount FROM dbo.splitdayexercises WHERE exerciseid = p_exerciseid;

    IF v_usagecount > 0 THEN
        RETURN NEXT dbo.outcome_cursor(2, p_exerciseid,
            'Used by ' || v_usagecount::text || ' split-day entry(s); remove it from those days first.');
        RETURN;
    END IF;

    DELETE FROM dbo.exercises WHERE exerciseid = p_exerciseid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Delete', 'Exercise', p_exerciseid::text,
            'Deleted exercise ''' || v_name || '''', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_exerciseid, NULL);
END $$;

-- =============================================================================
-- Meal suggestions
-- =============================================================================

CREATE OR REPLACE FUNCTION dbo.usp_admin_mealsuggestions_getall(
    p_suggestedmonth smallint DEFAULT NULL,
    p_mealtype text DEFAULT NULL,
    p_search text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_mealtype text := NULLIF(btrim(p_mealtype), '');
    v_search text := NULLIF(btrim(p_search), '');
BEGIN
    OPEN c1 FOR
    SELECT mealsuggestionid,
           title,
           mealtype,
           description,
           calorieskcal,
           proteing,
           carbsg,
           fatsg,
           suggestedmonth,
           issystemdefault,
           sortorder,
           createdatutc
    FROM dbo.mealsuggestions
    WHERE owneruserid IS NULL
      AND (p_suggestedmonth IS NULL OR suggestedmonth = p_suggestedmonth)
      AND (v_mealtype IS NULL OR mealtype = v_mealtype)
      AND (v_search IS NULL OR title LIKE '%' || v_search || '%')
    ORDER BY suggestedmonth NULLS FIRST, mealtype, sortorder, title;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_mealsuggestion_upsert(
    p_mealsuggestionid uuid DEFAULT NULL,
    p_title text DEFAULT NULL,
    p_mealtype text DEFAULT NULL,
    p_description text DEFAULT NULL,
    p_calorieskcal smallint DEFAULT NULL,
    p_proteing smallint DEFAULT NULL,
    p_carbsg smallint DEFAULT NULL,
    p_fatsg smallint DEFAULT NULL,
    p_suggestedmonth smallint DEFAULT NULL,
    p_sortorder integer DEFAULT 0,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_mealsuggestionid uuid := p_mealsuggestionid;
    v_title text := btrim(p_title);
    v_mealtype text := btrim(p_mealtype);
    v_description text := NULLIF(btrim(p_description), '');
    v_action text;
BEGIN
    IF v_title IS NULL OR v_title = '' THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A title is required.');
        RETURN;
    END IF;

    IF p_suggestedmonth IS NOT NULL AND (p_suggestedmonth < 1 OR p_suggestedmonth > 12) THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL,
            'Suggested month must be between 1 and 12, or left empty for a year-round suggestion.');
        RETURN;
    END IF;

    IF p_calorieskcal < 0 OR p_proteing < 0 OR p_carbsg < 0 OR p_fatsg < 0 THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'Calories and macros cannot be negative.');
        RETURN;
    END IF;

    IF v_mealsuggestionid IS NULL THEN
        v_mealsuggestionid := gen_random_uuid();
        v_action := 'Create';

        -- Operator-authored content is not part of the shipped default set, which is
        -- what issystemdefault marks (the seed files insert with it set to true).
        INSERT INTO dbo.mealsuggestions
            (mealsuggestionid, title, mealtype, description, calorieskcal, proteing, carbsg, fatsg,
             suggestedmonth, issystemdefault, sortorder)
        VALUES
            (v_mealsuggestionid, v_title, v_mealtype, v_description, p_calorieskcal, p_proteing, p_carbsg, p_fatsg,
             p_suggestedmonth, false, p_sortorder);
    ELSE
        v_action := 'Update';

        UPDATE dbo.mealsuggestions
        SET title = v_title,
            mealtype = v_mealtype,
            description = v_description,
            calorieskcal = p_calorieskcal,
            proteing = p_proteing,
            carbsg = p_carbsg,
            fatsg = p_fatsg,
            suggestedmonth = p_suggestedmonth,
            sortorder = p_sortorder
        WHERE mealsuggestionid = v_mealsuggestionid;

        IF NOT FOUND THEN
            RETURN NEXT dbo.outcome_cursor(1, v_mealsuggestionid, 'That suggestion no longer exists.');
            RETURN;
        END IF;
    END IF;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, v_action, 'MealSuggestion', v_mealsuggestionid::text,
            v_action || ' meal suggestion ''' || v_title || ''' (' || v_mealtype || ')', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_mealsuggestionid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_mealsuggestion_delete(
    p_mealsuggestionid uuid,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_title text;
BEGIN
    SELECT title INTO v_title FROM dbo.mealsuggestions WHERE mealsuggestionid = p_mealsuggestionid;

    IF v_title IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_mealsuggestionid, 'That suggestion no longer exists.');
        RETURN;
    END IF;

    DELETE FROM dbo.mealsuggestions WHERE mealsuggestionid = p_mealsuggestionid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Delete', 'MealSuggestion', p_mealsuggestionid::text,
            'Deleted meal suggestion ''' || v_title || '''', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_mealsuggestionid, NULL);
END $$;

-- =============================================================================
-- Subscription plans + their feature bullets
-- =============================================================================

CREATE OR REPLACE FUNCTION dbo.usp_admin_plans_getall()
RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT p.planid,
           p.code,
           p.name,
           p.tagline,
           p.monthlyprice,
           p.yearlyprice,
           p.isfeatured,
           p.sortorder,
           (SELECT COUNT(*)::int FROM dbo.planfeatures f WHERE f.planid = p.planid) AS featurecount,
           (SELECT COUNT(*)::int FROM dbo.usersubscriptions s
            WHERE s.planid = p.planid AND s.status = 'Active') AS activesubscribercount
    FROM dbo.subscriptionplans p
    ORDER BY p.sortorder, p.name;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_plan_upsert(
    p_planid uuid DEFAULT NULL,
    p_code text DEFAULT NULL,
    p_name text DEFAULT NULL,
    p_tagline text DEFAULT NULL,
    p_monthlyprice numeric DEFAULT NULL,
    p_yearlyprice numeric DEFAULT NULL,
    p_isfeatured boolean DEFAULT NULL,
    p_sortorder integer DEFAULT 0,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_planid uuid := p_planid;
    v_code text := btrim(p_code);
    v_name text := btrim(p_name);
    v_tagline text := NULLIF(btrim(p_tagline), '');
    v_action text;
BEGIN
    IF v_code IS NULL OR v_code = '' OR v_name IS NULL OR v_name = '' THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A plan needs both a code and a name.');
        RETURN;
    END IF;

    IF p_monthlyprice < 0 OR p_yearlyprice < 0 THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'Prices cannot be negative.');
        RETURN;
    END IF;

    -- Code is what the app and the pricing page key on, and it is unique in the
    -- schema; checked here so the console gets a sentence instead of a constraint
    -- violation.
    IF EXISTS (SELECT 1 FROM dbo.subscriptionplans
               WHERE code = v_code AND (v_planid IS NULL OR planid <> v_planid)) THEN
        RETURN NEXT dbo.outcome_cursor(2, NULL, 'Another plan already uses the code ''' || v_code || '''.');
        RETURN;
    END IF;

    IF v_planid IS NULL THEN
        v_planid := gen_random_uuid();
        v_action := 'Create';

        INSERT INTO dbo.subscriptionplans (planid, code, name, tagline, monthlyprice, yearlyprice, isfeatured, sortorder)
        VALUES (v_planid, v_code, v_name, v_tagline, p_monthlyprice, p_yearlyprice, p_isfeatured, p_sortorder);
    ELSE
        v_action := 'Update';

        UPDATE dbo.subscriptionplans
        SET code = v_code,
            name = v_name,
            tagline = v_tagline,
            monthlyprice = p_monthlyprice,
            yearlyprice = p_yearlyprice,
            isfeatured = p_isfeatured,
            sortorder = p_sortorder
        WHERE planid = v_planid;

        IF NOT FOUND THEN
            RETURN NEXT dbo.outcome_cursor(1, v_planid, 'That plan no longer exists.');
            RETURN;
        END IF;
    END IF;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, v_action, 'SubscriptionPlan', v_planid::text,
            v_action || ' plan ''' || v_name || ''' (' || v_code || ')', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_planid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_plan_delete(
    p_planid uuid,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_name text;
    v_subscribercount integer;
BEGIN
    SELECT name INTO v_name FROM dbo.subscriptionplans WHERE planid = p_planid;

    IF v_name IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_planid, 'That plan no longer exists.');
        RETURN;
    END IF;

    -- Any subscription row blocks the delete, not just active ones: those rows are
    -- the billing history and the FK is not cascading on purpose.
    SELECT COUNT(*) INTO v_subscribercount FROM dbo.usersubscriptions WHERE planid = p_planid;

    IF v_subscribercount > 0 THEN
        RETURN NEXT dbo.outcome_cursor(2, p_planid,
            '''' || v_name || ''' has ' || v_subscribercount::text
            || ' subscription record(s) and cannot be deleted. Rename or retire it instead.');
        RETURN;
    END IF;

    DELETE FROM dbo.planfeatures WHERE planid = p_planid;
    DELETE FROM dbo.subscriptionplans WHERE planid = p_planid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Delete', 'SubscriptionPlan', p_planid::text,
            'Deleted plan ''' || v_name || ''' and its feature list', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_planid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_planfeatures_getforplan(
    p_planid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT planfeatureid, planid, featuretext, sortorder, ishighlighted
    FROM dbo.planfeatures
    WHERE planid = p_planid
    ORDER BY sortorder, featuretext;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_planfeature_upsert(
    p_planfeatureid uuid DEFAULT NULL,
    p_planid uuid DEFAULT NULL,
    p_featuretext text DEFAULT NULL,
    p_sortorder smallint DEFAULT 0,
    p_ishighlighted boolean DEFAULT false,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_planfeatureid uuid := p_planfeatureid;
    v_featuretext text := btrim(p_featuretext);
    v_planname text;
    v_action text;
BEGIN
    IF v_featuretext IS NULL OR v_featuretext = '' THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A feature needs some text.');
        RETURN;
    END IF;

    SELECT name INTO v_planname FROM dbo.subscriptionplans WHERE planid = p_planid;

    IF v_planname IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_planid, 'That plan no longer exists.');
        RETURN;
    END IF;

    -- One row per perk: the plans screen lists every row, so a repeated text
    -- would show twice. Checked here so the console gets a sentence instead of
    -- a unique-index violation.
    IF EXISTS (SELECT 1 FROM dbo.planfeatures
               WHERE planid = p_planid AND featuretext = v_featuretext
                 AND (v_planfeatureid IS NULL OR planfeatureid <> v_planfeatureid)) THEN
        RETURN NEXT dbo.outcome_cursor(2, NULL, '''' || v_planname || ''' already lists that feature.');
        RETURN;
    END IF;

    IF v_planfeatureid IS NULL THEN
        v_planfeatureid := gen_random_uuid();
        v_action := 'Create';

        INSERT INTO dbo.planfeatures (planfeatureid, planid, featuretext, sortorder, ishighlighted)
        VALUES (v_planfeatureid, p_planid, v_featuretext, p_sortorder, p_ishighlighted);
    ELSE
        v_action := 'Update';

        UPDATE dbo.planfeatures
        SET featuretext = v_featuretext,
            sortorder = p_sortorder,
            ishighlighted = p_ishighlighted
        WHERE planfeatureid = v_planfeatureid;

        IF NOT FOUND THEN
            RETURN NEXT dbo.outcome_cursor(1, v_planfeatureid, 'That feature no longer exists.');
            RETURN;
        END IF;
    END IF;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, v_action, 'PlanFeature', v_planfeatureid::text,
            v_action || ' feature on plan ''' || v_planname || ''': ' || v_featuretext, p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_planfeatureid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_planfeature_delete(
    p_planfeatureid uuid,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_featuretext text;
    v_planname text;
BEGIN
    SELECT f.featuretext, p.name INTO v_featuretext, v_planname
    FROM dbo.planfeatures f
    INNER JOIN dbo.subscriptionplans p ON p.planid = f.planid
    WHERE f.planfeatureid = p_planfeatureid;

    IF v_featuretext IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_planfeatureid, 'That feature no longer exists.');
        RETURN;
    END IF;

    DELETE FROM dbo.planfeatures WHERE planfeatureid = p_planfeatureid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Delete', 'PlanFeature', p_planfeatureid::text,
            'Deleted feature from plan ''' || v_planname || ''': ' || v_featuretext, p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_planfeatureid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_planentitlements_getforplan(
    p_planid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT planid, maxactivesplits, maxactivedietplans, allowaigeneration
    FROM dbo.planentitlements
    WHERE planid = p_planid;
    RETURN NEXT c1;
END $$;

-- One row per plan (planid is the key, not a surrogate id).
CREATE OR REPLACE FUNCTION dbo.usp_admin_planentitlements_upsert(
    p_planid uuid,
    p_maxactivesplits integer DEFAULT NULL,
    p_maxactivedietplans integer DEFAULT NULL,
    p_allowaigeneration boolean DEFAULT false,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_planname text;
BEGIN
    IF p_maxactivesplits < 0 OR p_maxactivedietplans < 0 THEN
        RETURN NEXT dbo.outcome_cursor(3, p_planid, 'Limits cannot be negative. Leave a field blank for unlimited.');
        RETURN;
    END IF;

    SELECT name INTO v_planname FROM dbo.subscriptionplans WHERE planid = p_planid;

    IF v_planname IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_planid, 'That plan no longer exists.');
        RETURN;
    END IF;

    INSERT INTO dbo.planentitlements (planid, maxactivesplits, maxactivedietplans, allowaigeneration)
    VALUES (p_planid, p_maxactivesplits, p_maxactivedietplans, p_allowaigeneration)
    ON CONFLICT (planid) DO UPDATE
    SET maxactivesplits = EXCLUDED.maxactivesplits,
        maxactivedietplans = EXCLUDED.maxactivedietplans,
        allowaigeneration = EXCLUDED.allowaigeneration;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Update', 'PlanEntitlements', p_planid::text,
            'Set entitlements on plan ''' || v_planname || ''': splits='
            || COALESCE(p_maxactivesplits::text, 'unlimited') || ', diet plans='
            || COALESCE(p_maxactivedietplans::text, 'unlimited') || ', AI generation='
            || CASE WHEN p_allowaigeneration THEN 'on' ELSE 'off' END, p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_planid, NULL);
END $$;

-- =============================================================================
-- Users (read-only apart from the manual tier change below)
-- =============================================================================

CREATE OR REPLACE FUNCTION dbo.usp_admin_users_getall(
    p_search text DEFAULT NULL,
    p_limit integer DEFAULT 200
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_search text := NULLIF(btrim(p_search), '');
    v_limit integer := p_limit;
BEGIN
    IF v_limit IS NULL OR v_limit < 1 THEN v_limit := 200; END IF;
    IF v_limit > 500 THEN v_limit := 500; END IF;

    -- Account tier, join date and current subscription only. A user's own data
    -- (logs, bodyweight, nutrition) is served by the separately gated client
    -- overview in AdminClients.sql - users.data.read, plus an assigned-client
    -- check for trainers - and never by this list.
    OPEN c1 FOR
    SELECT u.userid,
           u.displayname,
           u.email,
           u.accounttier,
           u.isactive,
           u.createdatutc,
           u.lastloginatutc,
           p.code AS activeplancode,
           s.billingcycle,
           s.status AS subscriptionstatus,
           s.expiresatutc
    FROM dbo.users u
    LEFT JOIN dbo.usersubscriptions s ON s.userid = u.userid
    LEFT JOIN dbo.subscriptionplans p ON p.planid = s.planid
    WHERE (v_search IS NULL
           OR u.email LIKE '%' || v_search || '%'
           OR u.displayname LIKE '%' || v_search || '%')
    ORDER BY u.createdatutc DESC
    LIMIT v_limit;
    RETURN NEXT c1;
END $$;

-- Moves one app user onto a tier by hand (users.subscription.write). FREE has no
-- usersubscriptions row anywhere else in the app (see SubscriptionGate), so going
-- to Free deletes the row rather than leaving a cancelled paid one behind. A paid
-- tier is written the same way usp_subscription_purchase does, but detached from
-- any store receipt (latestreceiptid NULL, autorenewing false) so the row reads as
-- a manual grant. p_noexpiry = true makes the grant open-ended.
CREATE OR REPLACE FUNCTION dbo.usp_admin_user_setplan(
    p_userid uuid,
    p_plancode text,
    p_billingcycle text,
    p_noexpiry boolean DEFAULT false,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_userlabel text;
    v_planid uuid;
    v_planname text;
    v_expiresatutc timestamp(3);
BEGIN
    SELECT COALESCE(email, displayname, userid::text) INTO v_userlabel
    FROM dbo.users
    WHERE userid = p_userid;

    IF v_userlabel IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_userid, 'That user no longer exists.');
        RETURN;
    END IF;

    IF p_plancode IS DISTINCT FROM 'FREE' THEN
        SELECT planid, name INTO v_planid, v_planname FROM dbo.subscriptionplans WHERE code = p_plancode;

        IF v_planid IS NULL THEN
            RETURN NEXT dbo.outcome_cursor(3, p_userid, 'That plan does not exist.');
            RETURN;
        END IF;

        IF p_billingcycle IS NULL OR p_billingcycle COLLATE ci NOT IN ('Monthly', 'Yearly') THEN
            RETURN NEXT dbo.outcome_cursor(3, p_userid, 'Billing cycle must be Monthly or Yearly.');
            RETURN;
        END IF;

        v_expiresatutc := CASE
            WHEN p_noexpiry THEN NULL
            WHEN p_billingcycle COLLATE ci = 'Yearly' THEN dbo.sysutcdatetime() + interval '1 year'
            ELSE dbo.sysutcdatetime() + interval '1 month' END;
    END IF;

    IF v_planid IS NULL THEN
        DELETE FROM dbo.usersubscriptions WHERE userid = p_userid;
    ELSE
        INSERT INTO dbo.usersubscriptions
            (userid, planid, billingcycle, status, startedatutc, expiresatutc, latestreceiptid, autorenewing)
        VALUES (p_userid, v_planid, p_billingcycle, 'Active', dbo.sysutcdatetime(), v_expiresatutc, NULL, false)
        ON CONFLICT (userid) DO UPDATE
        SET planid = EXCLUDED.planid, billingcycle = EXCLUDED.billingcycle, status = 'Active',
            startedatutc = EXCLUDED.startedatutc, expiresatutc = EXCLUDED.expiresatutc,
            latestreceiptid = NULL, autorenewing = false;
    END IF;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Update', 'UserSubscription', p_userid::text,
            CASE WHEN v_planid IS NULL
                 THEN 'Moved ''' || v_userlabel || ''' to Free'
                 ELSE 'Moved ''' || v_userlabel || ''' to ' || v_planname || ' (' || p_billingcycle
                      || CASE WHEN p_noexpiry THEN ', no expiry' ELSE '' END || ')' END,
            p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_userid, NULL);
END $$;
