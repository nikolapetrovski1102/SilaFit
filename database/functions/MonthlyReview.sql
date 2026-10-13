-- Opens one monthly review run. RunId is generated here so the caller (and every
-- per-user delivery row written afterwards) shares the same identifier even if
-- the worker process is restarted mid-batch.
CREATE OR REPLACE FUNCTION dbo.usp_monthlyreview_startrun(
    p_periodyear smallint,
    p_periodmonth smallint,
    p_plancode varchar(30)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_runid uuid := gen_random_uuid();
BEGIN
    INSERT INTO dbo.monthlyreviewruns (runid, periodyear, periodmonth, plancode, status)
    VALUES (v_runid, p_periodyear, p_periodmonth, p_plancode, 'Running');

    OPEN c1 FOR
    SELECT runid, periodyear, periodmonth, plancode, status,
           usersconsidered, reportsgenerated, emailssent, failures,
           startedatutc, completedatutc
    FROM dbo.monthlyreviewruns
    WHERE runid = v_runid;
    RETURN NEXT c1;
END $$;

-- Finalises a run with its aggregate counters. Called even when some users
-- failed: Status stays 'Completed' and Failures captures the per-user errors
-- (full detail lives in MonthlyReviewDeliveries).
CREATE OR REPLACE FUNCTION dbo.usp_monthlyreview_completerun(
    p_runid uuid,
    p_status varchar(20),
    p_usersconsidered integer,
    p_reportsgenerated integer,
    p_emailssent integer,
    p_failures integer
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.monthlyreviewruns
    SET status = p_status,
        completedatutc = dbo.sysutcdatetime(),
        usersconsidered = p_usersconsidered,
        reportsgenerated = p_reportsgenerated,
        emailssent = p_emailssent,
        failures = p_failures
    WHERE runid = p_runid;
END $$;

-- Users who already received an email for this period, scoped to one audience
-- (Subscriber = full report, Upsell = non-paying teaser) because the two passes
-- are independent: a free user who upgrades mid-period must still be eligible
-- for the full report even though they already got the teaser.
CREATE OR REPLACE FUNCTION dbo.usp_monthlyreview_getemaileduserids(
    p_periodyear smallint,
    p_periodmonth smallint,
    p_deliverykind varchar(20)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT DISTINCT userid
    FROM dbo.monthlyreviewdeliveries
    WHERE periodyear = p_periodyear
      AND periodmonth = p_periodmonth
      AND deliverykind = p_deliverykind
      AND status = 'Emailed';
    RETURN NEXT c1;
END $$;

-- One audit row per user considered by a run: what happened (Generated /
-- Emailed / Skipped / Failed) and, on failure, why. p_deliverykind tags which
-- audience the row belongs to (Subscriber or Upsell).
CREATE OR REPLACE FUNCTION dbo.usp_monthlyreview_recorddelivery(
    p_runid uuid,
    p_userid uuid,
    p_periodyear smallint,
    p_periodmonth smallint,
    p_status varchar(20),
    p_errormessage varchar(1000) DEFAULT NULL,
    p_generatedatutc timestamp(3) DEFAULT NULL,
    p_emailedatutc timestamp(3) DEFAULT NULL,
    p_deliverykind varchar(20) DEFAULT 'Subscriber'
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO dbo.monthlyreviewdeliveries
        (deliveryid, runid, userid, periodyear, periodmonth, status, errormessage, generatedatutc, emailedatutc, deliverykind)
    VALUES
        (gen_random_uuid(), p_runid, p_userid, p_periodyear, p_periodmonth, p_status, p_errormessage, p_generatedatutc, p_emailedatutc, p_deliverykind);
END $$;
