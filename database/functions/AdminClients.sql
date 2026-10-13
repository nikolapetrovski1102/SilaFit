-- =============================================================================
-- Console client overview: "show me what this client actually logged".
--
-- Read-only, and gated by users.data.read / users.data.read_all in the service
-- layer (a trainer additionally has to be the one who assigned this user a split
-- or diet plan - see usp_Admin_Client_IsAssignedTo below).
--
-- Sensitive columns (UserProfiles body answers, MealLogs macros, BodyweightLogs
-- weight, UserNutritionTargets) are AES-256-GCM ciphertext; they are selected
-- as-is here and decrypted in AdminContentProvider, never in SQL - same split as
-- every other encrypted read in this codebase.
-- =============================================================================

-- Is p_userid one of the clients assigned by console operator p_adminuserid?
-- The assignment screens record who handed a split/diet plan over, which is the
-- client relationship the console lists.
CREATE OR REPLACE FUNCTION dbo.usp_admin_client_isassignedto(
    p_adminuserid uuid,
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT (
        EXISTS (SELECT 1 FROM dbo.splitassignments sa
                WHERE sa.userid = p_userid AND sa.assignedbyadminuserid = p_adminuserid)
        OR EXISTS (SELECT 1 FROM dbo.dietplanassignments da
                WHERE da.userid = p_userid AND da.assignedbyadminuserid = p_adminuserid)
    ) AS isassigned;
    RETURN NEXT c1;
END $$;

-- One client's overview over [p_fromdateutc, p_todateutc], as a series of result
-- sets the provider stitches into one model (the summary figures that need
-- decryption - calories, bodyweight - are computed in C#, not here).
CREATE OR REPLACE FUNCTION dbo.usp_admin_client_getoverview(
    p_userid uuid,
    p_fromdateutc date,
    p_todateutc date
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    c2 refcursor;
    c3 refcursor;
    c4 refcursor;
    c5 refcursor;
    c6 refcursor;
BEGIN
    -- 1) Account + onboarding profile (ciphertext) + active split/diet plan +
    --    nutrition targets (ciphertext). One row, or none if the user is gone.
    OPEN c1 FOR
    SELECT
        u.userid,
        u.displayname,
        u.email,
        u.accounttier,
        u.isactive,
        u.createdatutc,
        u.lastloginatutc,
        sub.activeplancode,
        sub.billingcycle,
        sub.subscriptionstatus,
        sub.expiresatutc,
        pr.gender,
        pr.ageyears,
        pr.heightcm,
        pr.weightkg,
        pr.goal,
        pr.trainingdaysperweek,
        pr.sessiondurationminutes,
        pr.trainingexperience,
        pr.equipmentaccess,
        pr.dailyactivitylevel,
        asp.splitid           AS activesplitid,
        asp.name              AS activesplitname,
        asp.category          AS activesplitcategory,
        asp.level             AS activesplitlevel,
        uas.activatedatutc    AS activesplitactivatedatutc,
        adp.dietplanid        AS activedietplanid,
        adp.name              AS activedietplanname,
        adp.periodtype        AS activedietplanperiodtype,
        uad.activatedatutc    AS activedietplanactivatedatutc,
        nt.targetcalories,
        nt.targetproteing,
        nt.targetcarbsg,
        nt.targetfatsg
    FROM dbo.users u
    LEFT JOIN dbo.userprofiles pr ON pr.userid = u.userid
    LEFT JOIN dbo.useractivesplits uas ON uas.userid = u.userid
    LEFT JOIN dbo.workoutsplits asp ON asp.splitid = uas.splitid
    LEFT JOIN dbo.useractivedietplans uad ON uad.userid = u.userid
    LEFT JOIN dbo.nutritionplans adp ON adp.dietplanid = uad.dietplanid
    LEFT JOIN dbo.usernutritiontargets nt ON nt.userid = u.userid
    LEFT JOIN LATERAL
    (
        SELECT p.code AS activeplancode,
               s.billingcycle,
               s.status AS subscriptionstatus,
               s.expiresatutc
        FROM dbo.usersubscriptions s
        JOIN dbo.subscriptionplans p ON p.planid = s.planid
        WHERE s.userid = u.userid
        ORDER BY s.expiresatutc DESC NULLS LAST
        LIMIT 1
    ) sub ON true
    WHERE u.userid = p_userid;
    RETURN NEXT c1;

    -- 2) Workout sessions in range, newest first.
    OPEN c2 FOR
    SELECT
        ws.workoutsessionid,
        ws.scheduleddateutc,
        ws.status,
        ws.startedatutc,
        ws.completedatutc,
        ws.durationminutes,
        ws.rpescore,
        ws.tonnagekg,
        sd.title AS splitdaytitle,
        sd.focuslabel AS splitdayfocus,
        (SELECT COUNT(*)::int FROM dbo.workoutsetlogs l WHERE l.workoutsessionid = ws.workoutsessionid) AS setcount
    FROM dbo.workoutsessions ws
    LEFT JOIN dbo.splitdays sd ON sd.splitdayid = ws.splitdayid
    WHERE ws.userid = p_userid
      AND ws.scheduleddateutc BETWEEN p_fromdateutc AND p_todateutc
    ORDER BY ws.scheduleddateutc DESC, ws.createdatutc DESC;
    RETURN NEXT c2;

    -- 3) Logged sets in range, newest first (bounded - the console shows a
    --    recent slice, not a lifetime export).
    OPEN c3 FOR
    SELECT
        l.workoutsetlogid,
        l.workoutsessionid,
        e.name AS exercisename,
        e.musclegroup,
        l.setnumber,
        l.weightkg,
        l.reps,
        l.completedatutc
    FROM dbo.workoutsetlogs l
    INNER JOIN dbo.exercises e ON e.exerciseid = l.exerciseid
    WHERE l.userid = p_userid
      AND l.completedatutc::date BETWEEN p_fromdateutc AND p_todateutc
    ORDER BY l.completedatutc DESC, l.setnumber ASC
    LIMIT 3000;
    RETURN NEXT c3;

    -- 4) Meals in range, newest first (macro columns are ciphertext).
    OPEN c4 FOR
    SELECT
        m.meallogid,
        m.logdateutc,
        m.mealtype,
        m.title,
        m.calorieskcal,
        m.proteing,
        m.carbsg,
        m.fatsg,
        m.status,
        m.loggedatutc
    FROM dbo.meallogs m
    WHERE m.userid = p_userid
      AND m.logdateutc BETWEEN p_fromdateutc AND p_todateutc
    ORDER BY m.logdateutc DESC, m.createdatutc DESC
    LIMIT 2000;
    RETURN NEXT c4;

    -- 5) Bodyweight in range, oldest first so the trend reads left to right
    --    (weight is ciphertext).
    OPEN c5 FOR
    SELECT
        b.bodyweightlogid,
        b.loggedatutc,
        b.weightkg
    FROM dbo.bodyweightlogs b
    WHERE b.userid = p_userid
      AND b.loggedatutc::date BETWEEN p_fromdateutc AND p_todateutc
    ORDER BY b.loggedatutc ASC
    LIMIT 1000;
    RETURN NEXT c5;

    -- 6) Hydration as one total per day in range.
    OPEN c6 FOR
    SELECT
        h.loggedatutc::date AS logdateutc,
        SUM(h.amountml)::int AS totalml
    FROM dbo.hydrationlogs h
    WHERE h.userid = p_userid
      AND h.loggedatutc::date BETWEEN p_fromdateutc AND p_todateutc
    GROUP BY h.loggedatutc::date
    ORDER BY logdateutc ASC;
    RETURN NEXT c6;
END $$;
