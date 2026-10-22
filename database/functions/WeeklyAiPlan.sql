-- Opens one weekly plan-generation run. RunId is generated here so every
-- per-user delivery row written afterwards shares the same identifier even if
-- the worker process is restarted mid-batch (see usp_MonthlyReview_StartRun,
-- which this mirrors).
CREATE OR REPLACE FUNCTION dbo.usp_weeklyaiplan_startrun(
    p_weekstartutc date
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_runid uuid := gen_random_uuid();
BEGIN
    INSERT INTO dbo.weeklyaiplanruns (runid, weekstartutc, status)
    VALUES (v_runid, p_weekstartutc, 'Running');

    OPEN c1 FOR
    SELECT runid, weekstartutc, status,
           usersconsidered, plansgenerated, notificationssent, failures,
           startedatutc, completedatutc
    FROM dbo.weeklyaiplanruns
    WHERE runid = v_runid;
    RETURN NEXT c1;
END $$;

-- Finalises a run with its aggregate counters. Status stays 'Completed' even
-- when some users failed - Failures captures the count and the per-user
-- detail lives in WeeklyAiPlanDeliveries.
CREATE OR REPLACE FUNCTION dbo.usp_weeklyaiplan_completerun(
    p_runid uuid,
    p_status varchar(20),
    p_usersconsidered integer,
    p_plansgenerated integer,
    p_notificationssent integer,
    p_failures integer
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.weeklyaiplanruns
    SET status = p_status,
        completedatutc = dbo.sysutcdatetime(),
        usersconsidered = p_usersconsidered,
        plansgenerated = p_plansgenerated,
        notificationssent = p_notificationssent,
        failures = p_failures
    WHERE runid = p_runid;
END $$;

-- Users already settled for this week - a delivery row exists whose split AND
-- diet outcome are both something other than 'Failed' (i.e. either
-- successfully 'Generated' or validly 'Skipped', for example for not enough
-- logged activity). A user with a 'Failed' delivery on either side is left
-- out, so a later re-run of the same week retries only the ones that didn't
-- finish - this is what makes a run safely re-runnable (mirrors
-- usp_MonthlyReview_GetEmailedUserIds).
CREATE OR REPLACE FUNCTION dbo.usp_weeklyaiplan_getprocesseduserids(
    p_weekstartutc date
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT DISTINCT userid
    FROM dbo.weeklyaiplandeliveries
    WHERE weekstartutc = p_weekstartutc
      AND splitstatus <> 'Failed'
      AND dietstatus <> 'Failed';
    RETURN NEXT c1;
END $$;

-- One audit row per user considered by a run: what happened to their split
-- and diet plan (Generated / Skipped / Failed independently), the resulting
-- ids, and when the "your plan is ready" notification went out.
CREATE OR REPLACE FUNCTION dbo.usp_weeklyaiplan_recorddelivery(
    p_runid uuid,
    p_userid uuid,
    p_weekstartutc date,
    p_splitstatus varchar(20),
    p_dietstatus varchar(20),
    p_splitid uuid DEFAULT NULL,
    p_dietplanid uuid DEFAULT NULL,
    p_errormessage varchar(1000) DEFAULT NULL,
    p_generatedatutc timestamp(3) DEFAULT NULL,
    p_notifiedatutc timestamp(3) DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO dbo.weeklyaiplandeliveries
        (deliveryid, runid, userid, weekstartutc, splitstatus, dietstatus, splitid, dietplanid, errormessage, generatedatutc, notifiedatutc)
    VALUES
        (gen_random_uuid(), p_runid, p_userid, p_weekstartutc, p_splitstatus, p_dietstatus, p_splitid, p_dietplanid, p_errormessage, p_generatedatutc, p_notifiedatutc);
END $$;

-- The weekly batch's audience: every active ADVANCED subscriber who has
-- consented to sharing their data with the third-party AI provider
-- (UserSettings.AiDataConsentAtUtc). Building a fresh weekly split/diet plan
-- is part of what the ADVANCED plan buys, but without that consent none of
-- the user's data may leave for the model. Generated diet plans become active automatically;
-- generated training splits remain recommendations until the user activates one.
CREATE OR REPLACE FUNCTION dbo.usp_weeklyaiplan_getcandidateusers(
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT
        u.userid,
        u.displayname,
        u.email,
        COALESCE(sp.entitlementcode, sp.code) AS plancode,
        us.expiresatutc
    FROM dbo.usersubscriptions us
    INNER JOIN dbo.subscriptionplans sp ON sp.planid = us.planid
    INNER JOIN dbo.users u ON u.userid = us.userid
    INNER JOIN dbo.usersettings st ON st.userid = u.userid
    WHERE COALESCE(sp.entitlementcode, sp.code) = 'ADVANCED'
      AND st.aidataconsentatutc IS NOT NULL
      AND us.status = 'Active'
      AND u.isactive
      AND (us.expiresatutc IS NULL OR us.expiresatutc > dbo.sysutcdatetime())
    ORDER BY u.createdatutc;
    RETURN NEXT c1;
END $$;
