-- Table access for Silen.Data.Providers.MockDataSeeder (the admin console's
-- "Mock data" action and the Silen.Tools.SeedMockData CLI).
--
-- The API logs in as silen_app, which can only EXECUTE dbo functions, so the
-- seeder can't run plain SELECT/INSERT/DELETE against the tables the way it did
-- on SQL Server. Each statement it needs lives here instead. Permission checks
-- (users.mock_data, super-admin only) live in the API, not here.

CREATE OR REPLACE FUNCTION dbo.usp_mockdata_userexists(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT EXISTS (SELECT 1 FROM dbo.users WHERE userid = p_userid) AS userexists;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_mockdata_setdisplayname(
    p_userid uuid,
    p_displayname varchar(100)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.users SET displayname = p_displayname WHERE userid = p_userid;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_mockdata_getplanid(
    p_code varchar(30)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT planid FROM dbo.subscriptionplans WHERE code = p_code;
    RETURN NEXT c1;
END $$;

-- Three result sets: the first system-default split in the category, its days,
-- and every exercise on those days.
CREATE OR REPLACE FUNCTION dbo.usp_mockdata_getsplit(
    p_category varchar(50)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    c2 refcursor;
    c3 refcursor;
    v_splitid uuid;
BEGIN
    SELECT splitid INTO v_splitid
    FROM dbo.workoutsplits
    WHERE issystemdefault AND category = p_category
    ORDER BY sortorder
    LIMIT 1;

    OPEN c1 FOR
    SELECT splitid, name, durationdays FROM dbo.workoutsplits WHERE splitid = v_splitid;
    RETURN NEXT c1;

    OPEN c2 FOR
    SELECT splitdayid, dayindex, estimatedminutes, isrestday
    FROM dbo.splitdays
    WHERE splitid = v_splitid
    ORDER BY dayindex;
    RETURN NEXT c2;

    OPEN c3 FOR
    SELECT sde.splitdayid, sde.exerciseid, e.iscompound, sde.targetsets, sde.targetrepslow, sde.targetrepshigh
    FROM dbo.splitdayexercises sde
    INNER JOIN dbo.exercises e ON e.exerciseid = sde.exerciseid
    WHERE sde.splitdayid IN (SELECT splitdayid FROM dbo.splitdays WHERE splitid = v_splitid)
    ORDER BY sde.splitdayid, sde.sortorder;
    RETURN NEXT c3;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_mockdata_activatesplit(
    p_userid uuid,
    p_splitid uuid,
    p_activatedatutc timestamp(3)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO dbo.useractivesplits (userid, splitid, activatedatutc)
    VALUES (p_userid, p_splitid, p_activatedatutc)
    ON CONFLICT (userid) DO UPDATE SET splitid = EXCLUDED.splitid, activatedatutc = EXCLUDED.activatedatutc;
END $$;

-- Cached recaps contain snapshots of the logs below. They must be invalidated in
-- the same seed operation or a test account can keep showing a pre-seed
-- weekly/monthly report until its cache expires.
CREATE OR REPLACE FUNCTION dbo.usp_mockdata_wipe(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM dbo.weeklyanalyticsreports WHERE userid = p_userid;
    DELETE FROM dbo.monthlyanalyticsreports WHERE userid = p_userid;
    DELETE FROM dbo.workoutsetlogs WHERE userid = p_userid;
    DELETE FROM dbo.workoutsessions WHERE userid = p_userid;
    DELETE FROM dbo.meallogs WHERE userid = p_userid;
    DELETE FROM dbo.hydrationlogs WHERE userid = p_userid;
    DELETE FROM dbo.bodyweightlogs WHERE userid = p_userid;
END $$;

-- One session plus all of its sets in one call; the set arrays are parallel
-- (element i of each describes set i) and empty for a rest or missed day.
CREATE OR REPLACE FUNCTION dbo.usp_mockdata_insertworkout(
    p_userid uuid,
    p_splitdayid uuid,
    p_scheduleddateutc date,
    p_status varchar(20),
    p_startedatutc timestamp(3) DEFAULT NULL,
    p_completedatutc timestamp(3) DEFAULT NULL,
    p_durationminutes smallint DEFAULT NULL,
    p_caloriesestimate smallint DEFAULT NULL,
    p_rpescore numeric(3,1) DEFAULT NULL,
    p_tonnagekg numeric(10,2) DEFAULT NULL,
    p_exerciseids uuid[] DEFAULT '{}',
    p_setnumbers smallint[] DEFAULT '{}',
    p_weightskg numeric[] DEFAULT '{}',
    p_reps smallint[] DEFAULT '{}'
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_sessionid uuid;
BEGIN
    INSERT INTO dbo.workoutsessions
        (userid, splitdayid, scheduleddateutc, status, startedatutc, completedatutc,
         durationminutes, caloriesestimate, rpescore, tonnagekg)
    VALUES
        (p_userid, p_splitdayid, p_scheduleddateutc, p_status, p_startedatutc, p_completedatutc,
         p_durationminutes, p_caloriesestimate, p_rpescore, p_tonnagekg)
    RETURNING workoutsessionid INTO v_sessionid;

    INSERT INTO dbo.workoutsetlogs (workoutsessionid, userid, exerciseid, setnumber, weightkg, reps, completedatutc)
    SELECT v_sessionid, p_userid, s.exerciseid, s.setnumber, s.weightkg, s.reps,
           COALESCE(p_completedatutc, dbo.sysutcdatetime())
    FROM unnest(p_exerciseids, p_setnumbers, p_weightskg, p_reps) AS s(exerciseid, setnumber, weightkg, reps);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_mockdata_inserthydration(
    p_userid uuid,
    p_loggedatutc timestamp(3),
    p_amountml smallint
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO dbo.hydrationlogs (userid, loggedatutc, amountml)
    VALUES (p_userid, p_loggedatutc, p_amountml);
END $$;

-- p_weightkg is FieldCipher ciphertext, encrypted by the caller.
CREATE OR REPLACE FUNCTION dbo.usp_mockdata_insertbodyweight(
    p_userid uuid,
    p_loggedatutc timestamp(3),
    p_weightkg bytea
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO dbo.bodyweightlogs (userid, loggedatutc, weightkg)
    VALUES (p_userid, p_loggedatutc, p_weightkg);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_mockdata_writeaudit(
    p_adminuserid uuid,
    p_username varchar(100),
    p_entityid varchar(64),
    p_summary varchar(500),
    p_ip varchar(64) DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_adminuserid, p_username, 'Seed mock data', 'User', p_entityid, p_summary, p_ip);
END $$;
