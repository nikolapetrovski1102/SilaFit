-- Registers (or refreshes) a push token for a user and, when supplied, the
-- timezone + notification opt-in that go with it. Called from onboarding the
-- moment the OS prompt is answered, so the very first reminder is already
-- scheduled against the device's own clock rather than the server's.
--
-- p_token is nullable: opting in with no push token yet still persists the
-- timezone/opt-in, so the app can call this twice (once on permission, once
-- once FCM hands back a token) without either call being a no-op.
CREATE OR REPLACE FUNCTION dbo.usp_notification_registerdevicetoken(
    p_userid uuid,
    p_token varchar(512) DEFAULT NULL,
    p_platform varchar(20) DEFAULT 'unknown',
    p_timezoneid varchar(100) DEFAULT NULL,
    p_notificationsenabled boolean DEFAULT NULL,
    p_nowutc timestamp(3) DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    IF p_timezoneid IS NOT NULL OR p_notificationsenabled IS NOT NULL THEN
        UPDATE dbo.usersettings
        SET timezoneid           = COALESCE(p_timezoneid, timezoneid),
            notificationsenabled = COALESCE(p_notificationsenabled, notificationsenabled),
            updatedatutc         = p_nowutc
        WHERE userid = p_userid;
    END IF;

    IF p_token IS NOT NULL THEN
        INSERT INTO dbo.userdevicetokens (userid, platform, pushtoken, timezoneid, lastseenatutc, updatedatutc)
        VALUES (p_userid, p_platform, p_token, p_timezoneid, p_nowutc, p_nowutc)
        ON CONFLICT (pushtoken) DO UPDATE SET
            userid        = EXCLUDED.userid,
            platform      = EXCLUDED.platform,
            timezoneid    = COALESCE(EXCLUDED.timezoneid, userdevicetokens.timezoneid),
            isactive      = true,
            lastseenatutc = EXCLUDED.lastseenatutc,
            updatedatutc  = EXCLUDED.updatedatutc;
    END IF;

    -- Opting in/refreshing counts as an interaction. Without this, a brand-new
    -- user would look "gone quiet" (their only timestamp being account
    -- creation) and get the comeback message on day one.
    INSERT INTO dbo.usernotificationstates (userid, lastinteractionatutc, updatedatutc)
    VALUES (p_userid, p_nowutc, p_nowutc)
    ON CONFLICT (userid) DO UPDATE SET
        lastinteractionatutc = EXCLUDED.lastinteractionatutc,
        updatedatutc         = EXCLUDED.updatedatutc;
END $$;

-- Deactivates one token (sign-out, permission revoked, or the provider told us
-- it is unregistered). Kept rather than deleted so re-registering revives it.
CREATE OR REPLACE FUNCTION dbo.usp_notification_deactivatedevicetoken(
    p_userid uuid,
    p_token varchar(512)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.userdevicetokens
    SET isactive     = false,
        updatedatutc = dbo.sysutcdatetime()
    WHERE userid = p_userid
      AND pushtoken = p_token;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_notification_getactivedevicetokens(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT devicetokenid, userid, platform, pushtoken, timezoneid, isactive,
           createdatutc, updatedatutc, lastseenatutc
    FROM dbo.userdevicetokens
    WHERE userid = p_userid
      AND isactive
    ORDER BY lastseenatutc DESC;
    RETURN NEXT c1;
END $$;

-- Records that the user actually used the app (foreground/open, or tapped a
-- notification). This is the heartbeat the backoff logic measures: too long a
-- gap and normal reminders quiet down, then a single comeback message fires.
CREATE OR REPLACE FUNCTION dbo.usp_notification_recordinteraction(
    p_userid uuid,
    p_atutc timestamp(3),
    p_notificationid uuid DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO dbo.usernotificationstates (userid, lastinteractionatutc, updatedatutc)
    VALUES (p_userid, p_atutc, p_atutc)
    ON CONFLICT (userid) DO UPDATE SET
        lastinteractionatutc = EXCLUDED.lastinteractionatutc,
        updatedatutc         = EXCLUDED.updatedatutc;

    IF p_notificationid IS NOT NULL THEN
        UPDATE dbo.usernotifications
        SET openedatutc = p_atutc,
            status      = 'Opened'
        WHERE notificationid = p_notificationid
          AND userid = p_userid
          AND status IN ('Created', 'Sent');
    END IF;
END $$;

-- Every opted-in user with at least one active device token, plus the raw facts
-- the scheduler needs to decide what (if anything) to send. All timestamps come
-- back in UTC; the service converts to each user's timezone in memory, so this
-- never has to know about IANA/Windows zone names.
--
-- p_maxusers is applied here, not in the caller, so a single run's cost doesn't
-- scale with the whole user base. Ordering by UserId is deterministic; once the
-- opted-in base can exceed p_maxusers, the next step is a persisted keyset cursor.
CREATE OR REPLACE FUNCTION dbo.usp_notificationpublish_getcandidates(
    p_maxusers integer DEFAULT 5000
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_now timestamp := dbo.sysutcdatetime();
BEGIN
    OPEN c1 FOR
    WITH tokencounts AS (
        SELECT userid, COUNT(*)::int AS activetokencount
        FROM dbo.userdevicetokens
        WHERE isactive
        GROUP BY userid
    ),
    workouts AS (
        SELECT userid,
               MAX(startedatutc)   AS lastworkoutstartedatutc,
               MAX(completedatutc) AS lastworkoutcompletedatutc,
               COUNT(CASE WHEN completedatutc >= v_now - interval '7 days' THEN 1 END)::int AS workoutslast7days,
               -- Raw history for ReminderTimeDetector: when this user actually trains.
               array_agg(startedatutc) FILTER (WHERE startedatutc >= v_now - interval '28 days') AS recentworkoutstartsutc
        FROM dbo.workoutsessions
        GROUP BY userid
    ),
    activesessions AS (
        SELECT userid,
               MAX(startedatutc)      AS activesessionstartedatutc,
               MAX(lastactivityatutc) AS activesessionlastactivityatutc
        FROM dbo.workoutsessions
        WHERE startedatutc IS NOT NULL
          AND completedatutc IS NULL
        GROUP BY userid
    ),
    mealstats AS (
        SELECT userid,
               MAX(loggedatutc) AS lastmealloggedatutc,
               COUNT(CASE WHEN loggedatutc >= v_now - interval '24 hours' THEN 1 END)::int AS mealslast24h,
               -- Raw history for ReminderTimeDetector: when this user actually logs meals.
               array_agg(loggedatutc) FILTER (WHERE loggedatutc >= v_now - interval '28 days') AS recentmealsloggedutc
        FROM dbo.meallogs
        WHERE status = 'Logged'
        GROUP BY userid
    ),
    notificationstats AS (
        SELECT userid,
               COUNT(CASE WHEN sentatutc >= v_now - interval '24 hours' THEN 1 END)::int AS sentlast24h
        FROM dbo.usernotifications
        GROUP BY userid
    )
    SELECT
        u.userid,
        u.displayname,
        s.notificationsenabled,
        s.notificationlocaltime,
        s.notificationtimeisuserset,
        s.timezoneid,
        COALESCE(st.lastinteractionatutc, u.lastloginatutc, u.createdatutc) AS lastinteractionatutc,
        st.lastpushedatutc,
        st.lastmotivationatutc,
        st.lastcomebackatutc,
        COALESCE(ns.sentlast24h, 0) AS sentlast24h,
        w.lastworkoutstartedatutc,
        w.lastworkoutcompletedatutc,
        COALESCE(w.workoutslast7days, 0) AS workoutslast7days,
        w.recentworkoutstartsutc,
        a.activesessionstartedatutc,
        a.activesessionlastactivityatutc,
        m.lastmealloggedatutc,
        COALESCE(m.mealslast24h, 0) AS mealslast24h,
        m.recentmealsloggedutc,
        -- Drives the monthly-review upsell: only non-paying users (no active
        -- PRO/ADVANCED entitlement) get the "unlock your review" push. Same
        -- plan-code set as SubscriptionGate.ProPlanCodes and
        -- usp_Plans_GetNonSubscribers.
        EXISTS (
            SELECT 1
            FROM dbo.usersubscriptions us
            INNER JOIN dbo.subscriptionplans sp ON sp.planid = us.planid
            WHERE us.userid = u.userid
              AND us.status = 'Active'
              AND (us.expiresatutc IS NULL OR us.expiresatutc > v_now)
              AND COALESCE(sp.entitlementcode, sp.code) IN ('PRO', 'ADVANCED')
        ) AS haspaidsubscription,
        tc.activetokencount
    FROM dbo.usersettings s
    INNER JOIN dbo.users u ON u.userid = s.userid
    INNER JOIN tokencounts tc ON tc.userid = s.userid
    LEFT JOIN dbo.usernotificationstates st ON st.userid = s.userid
    LEFT JOIN workouts w ON w.userid = s.userid
    LEFT JOIN activesessions a ON a.userid = s.userid
    LEFT JOIN mealstats m ON m.userid = s.userid
    LEFT JOIN notificationstats ns ON ns.userid = s.userid
    -- NOTE: UserNutritionTargets is deliberately not joined. Its TargetCalories
    -- is an encrypted bytea column, so it must only be read through the
    -- decrypting provider, not in raw reporting SQL like this.
    WHERE s.notificationsenabled
      AND u.isactive
    ORDER BY u.userid
    LIMIT p_maxusers;
    RETURN NEXT c1;
END $$;

-- Enqueues one notification unless its dedupe key already exists for the user.
-- Returns the created row, or an empty set when it was a duplicate - that empty
-- result is what lets the batch run every few minutes without re-sending.
-- (ON CONFLICT against the (UserId, DedupeKey) unique index is what keeps two
-- overlapping runs from both inserting.)
CREATE OR REPLACE FUNCTION dbo.usp_notificationpublish_trycreate(
    p_userid uuid,
    p_category varchar(30),
    p_title varchar(120),
    p_body varchar(500),
    p_deeplink varchar(200) DEFAULT NULL,
    p_dedupekey varchar(120) DEFAULT NULL,
    p_scheduledlocalat timestamp(3) DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_notificationid uuid;
BEGIN
    INSERT INTO dbo.usernotifications
        (notificationid, userid, category, title, body, deeplink, dedupekey, status, scheduledlocalat)
    VALUES (gen_random_uuid(), p_userid, p_category, p_title, p_body, p_deeplink, p_dedupekey, 'Created', p_scheduledlocalat)
    ON CONFLICT (userid, dedupekey) DO NOTHING
    RETURNING notificationid INTO v_notificationid;

    OPEN c1 FOR
    SELECT notificationid, userid, category, title, body, deeplink, dedupekey, status,
           providermessageid, errormessage, scheduledlocalat, sentatutc, openedatutc, createdatutc
    FROM dbo.usernotifications
    WHERE notificationid = v_notificationid;
    RETURN NEXT c1;
END $$;

-- Marks a notification delivered and advances the per-user cooldown state
-- (last push, and the two low-frequency category timestamps).
CREATE OR REPLACE FUNCTION dbo.usp_notificationpublish_marksent(
    p_notificationid uuid,
    p_category varchar(30),
    p_providermessageid varchar(200) DEFAULT NULL,
    p_sentatutc timestamp(3) DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_userid uuid;
BEGIN
    UPDATE dbo.usernotifications
    SET status            = 'Sent',
        providermessageid = p_providermessageid,
        sentatutc         = p_sentatutc,
        errormessage      = NULL
    WHERE notificationid = p_notificationid
    RETURNING userid INTO v_userid;

    IF v_userid IS NULL THEN
        RETURN;
    END IF;

    INSERT INTO dbo.usernotificationstates
        (userid, lastpushedatutc, pushedcount, lastmotivationatutc, lastcomebackatutc, updatedatutc)
    VALUES
        (v_userid, p_sentatutc, 1,
         CASE WHEN p_category = 'Motivation' THEN p_sentatutc END,
         CASE WHEN p_category = 'Comeback' THEN p_sentatutc END,
         dbo.sysutcdatetime())
    ON CONFLICT (userid) DO UPDATE SET
        lastpushedatutc     = p_sentatutc,
        pushedcount         = usernotificationstates.pushedcount + 1,
        lastmotivationatutc = CASE WHEN p_category = 'Motivation' THEN p_sentatutc ELSE usernotificationstates.lastmotivationatutc END,
        lastcomebackatutc   = CASE WHEN p_category = 'Comeback' THEN p_sentatutc ELSE usernotificationstates.lastcomebackatutc END,
        updatedatutc        = dbo.sysutcdatetime();
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_notificationpublish_markfailed(
    p_notificationid uuid,
    p_errormessage varchar(1000)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.usernotifications
    SET status       = 'Failed',
        errormessage = p_errormessage
    WHERE notificationid = p_notificationid;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_notificationpublish_markskipped(
    p_notificationid uuid,
    p_reason varchar(500)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.usernotifications
    SET status       = 'Skipped',
        errormessage = p_reason
    WHERE notificationid = p_notificationid;
END $$;

-- Safety net for the outbox. A normal run creates a notification and delivers it
-- in the same pass (usp_NotificationPublish_TryCreate -> MarkSent/Failed/Skipped),
-- so a row left in 'Created' means the process died mid-flight or the transport
-- failed before the row reached a terminal status. This feed lets a later run
-- retry those rows instead of stranding them forever.
--
-- p_olderthanutc is the grace cutoff: the create -> deliver window is
-- milliseconds, so anything older than a few minutes is genuinely orphaned, and
-- a run that is merely in-flight is left alone. Ordered oldest-first so the
-- longest-stranded notifications are retried first under the p_maxrows cap.
CREATE OR REPLACE FUNCTION dbo.usp_notificationpublish_getpending(
    p_olderthanutc timestamp(3),
    p_maxrows integer DEFAULT 200
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT notificationid, userid, category, title, body, deeplink, dedupekey, status,
           providermessageid, errormessage, scheduledlocalat, sentatutc, openedatutc, createdatutc
    FROM dbo.usernotifications
    WHERE status = 'Created'
      AND createdatutc < p_olderthanutc
    ORDER BY createdatutc
    LIMIT p_maxrows;
    RETURN NEXT c1;
END $$;
