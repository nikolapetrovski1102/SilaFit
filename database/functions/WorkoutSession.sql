-- Idempotently resolves (creating if needed) today's scheduled session from
-- the user's active split rotation, then returns the session header
-- (result set 1) and its target exercises (result set 2).
CREATE OR REPLACE FUNCTION dbo.usp_workoutsession_gettodayscheduled(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    c2 refcursor;
    v_today date := dbo.sysutcdatetime()::date;
    v_splitid uuid;
    v_activateddate date;
    v_durationdays integer;
    v_splitdayid uuid;
    v_anchordate date;
    v_maxdayindex integer;
    v_spandays integer;
    v_cyclelength integer;
    v_cycleindex integer;
    v_workoutsessionid uuid;
    v_existingsplitdayid uuid;
    v_isunderway boolean;
BEGIN
    -- Two app screens resolving today at once would otherwise both see no
    -- session and both insert one.
    PERFORM pg_advisory_xact_lock(hashtextextended('today-session:' || p_userid::text, 0));

    SELECT uas.splitid, uas.activatedatutc::date, ws.durationdays
    INTO v_splitid, v_activateddate, v_durationdays
    FROM dbo.useractivesplits uas
    INNER JOIN dbo.workoutsplits ws ON ws.splitid = uas.splitid
    WHERE uas.userid = p_userid;

    IF v_splitid IS NOT NULL THEN
        -- The rotation is anchored to the Monday of the activation week, so
        -- every split's first day lands on a Monday (activating mid-week picks
        -- up at that weekday's slot). Same anchor as usp_Streak_GetStatus.
        v_anchordate := date_trunc('week', v_activateddate)::date;

        -- The rotation is whole weeks long so Day 1 lands on every Monday,
        -- not just the first: a 4-day split trains Mon-Thu and rests the rest
        -- of the week rather than cycling every 4 days. It spans DurationDays
        -- or the highest authored DayIndex, whichever is larger, rounded up to
        -- a multiple of 7 (so a 10-day split rotates every two weeks).
        SELECT MAX(dayindex) INTO v_maxdayindex FROM dbo.splitdays WHERE splitid = v_splitid;
        v_spandays := CASE WHEN COALESCE(v_maxdayindex, 0) > v_durationdays THEN v_maxdayindex ELSE v_durationdays END;
        v_cyclelength := 7 * ((CASE WHEN v_spandays < 1 THEN 1 ELSE v_spandays END + 6) / 7);

        -- 0-based position within the split's rotation. Normalised to be
        -- non-negative so a future ActivatedAtUtc (clock skew) can't index
        -- backwards - same convention as the Dart resolver and the mock seeder.
        v_cycleindex := (((v_today - v_anchordate) % v_cyclelength) + v_cyclelength) % v_cyclelength;

        -- Match on the stored DayIndex (1-based - every save path enforces
        -- 1..14), not on ordinal position: a split numbered Day 1, Day 2, Day 4
        -- rests on Day 3 instead of pulling Day 4 forward. A slot with no
        -- SplitDay leaves v_splitdayid NULL, i.e. an implicit rest day.
        SELECT splitdayid INTO v_splitdayid
        FROM dbo.splitdays
        WHERE splitid = v_splitid AND dayindex = v_cycleindex + 1;
    END IF;

    SELECT workoutsessionid, splitdayid,
           firstsetcompletedatutc IS NOT NULL OR completedatutc IS NOT NULL
    INTO v_workoutsessionid, v_existingsplitdayid, v_isunderway
    FROM dbo.workoutsessions
    WHERE userid = p_userid AND scheduleddateutc = v_today;

    IF v_workoutsessionid IS NULL AND v_splitdayid IS NOT NULL THEN
        v_workoutsessionid := gen_random_uuid();

        INSERT INTO dbo.workoutsessions (workoutsessionid, userid, splitdayid, scheduleddateutc, status)
        VALUES (v_workoutsessionid, p_userid, v_splitdayid, v_today, 'Scheduled');
    ELSIF v_workoutsessionid IS NOT NULL AND NOT v_isunderway
          AND v_existingsplitdayid IS DISTINCT FROM v_splitdayid THEN
        -- Today's session already exists but the user switched splits (or
        -- their split day's ordinal shifted) before doing any of it, so
        -- re-point it at the newly active split's day instead of leaving it
        -- stuck on the old one. Once a set has been ticked off (or the
        -- session is completed) a switch must not yank the split out from
        -- under that workout. StartedAtUtc is deliberately not the signal:
        -- it is stamped by merely opening the tracker, so peeking at today's
        -- workout and backing out would otherwise lock the old split in.
        UPDATE dbo.workoutsessions
        SET splitdayid = v_splitdayid
        WHERE workoutsessionid = v_workoutsessionid;
    END IF;

    OPEN c1 FOR
    SELECT
        ws.workoutsessionid, ws.status, ws.scheduleddateutc,
        sd.splitdayid, sd.title, sd.focuslabel, sd.estimatedminutes, sd.isrestday
    FROM dbo.workoutsessions ws
    LEFT JOIN dbo.splitdays sd ON sd.splitdayid = ws.splitdayid
    WHERE ws.userid = p_userid AND ws.scheduleddateutc = v_today;
    RETURN NEXT c1;

    OPEN c2 FOR
    SELECT e.exerciseid, e.name, e.musclegroup, e.equipmenttype, e.demovideourl, sde.sortorder, sde.targetsets, sde.targetrepslow, sde.targetrepshigh
    FROM dbo.splitdayexercises sde
    INNER JOIN dbo.exercises e ON e.exerciseid = sde.exerciseid
    WHERE sde.splitdayid = v_splitdayid
    ORDER BY sde.sortorder;
    RETURN NEXT c2;
END $$;

-- p_setlogsjson: JSON array of {"exerciseId","setNumber","weightKg","reps"} -
-- the set-by-set log behind real Personal Records (see
-- usp_WorkoutSession_GetPersonalRecords). NULL/absent is a valid, older-client
-- call: the session still completes, it just adds nothing to PR history.
--
-- p_splitdayid / p_scheduleddateutc: set only for a session the phone made up
-- itself because it couldn't reach usp_workoutsession_gettodayscheduled (a
-- gym with no signal, app not opened yet that day). When no session has
-- p_workoutsessionid, that day's session is completed instead - the server
-- may have created one since - or, failing that, created under the phone's id.
CREATE OR REPLACE FUNCTION dbo.usp_workoutsession_complete(
    p_userid uuid,
    p_workoutsessionid uuid,
    p_durationminutes smallint,
    p_caloriesestimate smallint DEFAULT NULL,
    p_rpescore numeric(3,1) DEFAULT NULL,
    p_tonnagekg numeric(10,2) DEFAULT NULL,
    p_setlogsjson text DEFAULT NULL,
    p_completedatutc timestamp(3) DEFAULT NULL,
    p_splitdayid uuid DEFAULT NULL,
    p_scheduleddateutc date DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    -- A workout finished offline in the gym is uploaded later; the client
    -- sends when it actually ended (already clamped by TodayService) so the
    -- session and its sets land on the right day for streaks and PRs.
    v_completedatutc timestamp(3) := COALESCE(p_completedatutc, dbo.sysutcdatetime());
    v_scheduleddate date := COALESCE(p_scheduleddateutc, v_completedatutc::date);
    v_workoutsessionid uuid := p_workoutsessionid;
BEGIN
    IF p_splitdayid IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM dbo.workoutsessions
        WHERE workoutsessionid = p_workoutsessionid AND userid = p_userid
    ) THEN
        -- Same lock as usp_workoutsession_gettodayscheduled, so the two can't
        -- each create that day's session.
        PERFORM pg_advisory_xact_lock(hashtextextended('today-session:' || p_userid::text, 0));

        SELECT workoutsessionid INTO v_workoutsessionid
        FROM dbo.workoutsessions
        WHERE userid = p_userid AND scheduleddateutc = v_scheduleddate
        LIMIT 1;

        IF v_workoutsessionid IS NULL
           AND EXISTS (SELECT 1 FROM dbo.splitdays WHERE splitdayid = p_splitdayid) THEN
            v_workoutsessionid := p_workoutsessionid;
            INSERT INTO dbo.workoutsessions (workoutsessionid, userid, splitdayid, scheduleddateutc, status)
            VALUES (v_workoutsessionid, p_userid, p_splitdayid, v_scheduleddate, 'Scheduled');
        END IF;
        -- Otherwise the split day was deleted before the upload: nothing to
        -- attach the workout to, so it falls through as not found.
    END IF;

    UPDATE dbo.workoutsessions
    SET status = 'Completed',
        completedatutc = v_completedatutc,
        durationminutes = p_durationminutes,
        caloriesestimate = p_caloriesestimate,
        rpescore = p_rpescore,
        tonnagekg = p_tonnagekg
    WHERE workoutsessionid = v_workoutsessionid AND userid = p_userid;

    -- Idempotent: completing the same session twice (a retried request)
    -- replaces its set log rather than duplicating every set.
    DELETE FROM dbo.workoutsetlogs WHERE workoutsessionid = v_workoutsessionid AND userid = p_userid;

    IF v_workoutsessionid IS NOT NULL AND p_setlogsjson IS NOT NULL AND p_setlogsjson IS JSON ARRAY
       AND EXISTS (SELECT 1 FROM dbo.workoutsessions WHERE workoutsessionid = v_workoutsessionid AND userid = p_userid) THEN
        INSERT INTO dbo.workoutsetlogs (workoutsessionid, userid, exerciseid, setnumber, weightkg, reps, completedatutc)
        SELECT v_workoutsessionid, p_userid, j."exerciseId", j."setNumber", j."weightKg", j.reps, v_completedatutc
        FROM jsonb_to_recordset(p_setlogsjson::jsonb)
            AS j("exerciseId" uuid, "setNumber" smallint, "weightKg" numeric(6,2), reps smallint);
    END IF;

    OPEN c1 FOR
    SELECT workoutsessionid, status, completedatutc, durationminutes, caloriesestimate, rpescore, tonnagekg
    FROM dbo.workoutsessions
    WHERE workoutsessionid = v_workoutsessionid AND userid = p_userid;
    RETURN NEXT c1;
END $$;

-- How many times a set's logged weight counts toward volume: 2 for a Dumbbell
-- exercise done with a dumbbell in each hand (the set log stores the weight
-- per hand), 1 for everything else - single-dumbbell moves (goblet squat,
-- pullover, one-arm row, ...), barbells, machines. Mirrors
-- `_loadMultiplierFor` in active_workout_tracker_screen.dart and migration
-- 0012 - keep the three in step.
CREATE OR REPLACE FUNCTION dbo.ufn_exercise_loadmultiplier(
    p_equipmenttype varchar,
    p_name varchar
) RETURNS integer LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_equipmenttype = 'Dumbbell'
                 AND NOT (p_name COLLATE "C" ~* (
                     'goblet|single[ -]arm|one[ -]arm|1-arm|tripod|pull ?over|concentration'
                     '|plie|sumo squat|side bend|knee-in|pass-through'
                     '|two arm dumbbell overhead|two arm seated dumbbell'
                     '|overhead dumbbell (extension|tricep)|dumbbell overhead (extension|tricep)'
                     '|dumbbell tricep overhead|seated dumbbell tricep extension'
                     '|triceps press with db|overhead triceps|behind head|french press'
                     '|weighted (ab )?crunch|1 db|dumbbell on chest'))
                THEN 2 ELSE 1 END;
$$;

-- Feeds the Progress screen's Personal Records card: the heaviest set ever
-- logged per exercise, plus whatever the heaviest set was *before* that one
-- (to show a real "+Xkg" delta) - NULL when the PR is the only set ever
-- logged for that exercise.
CREATE OR REPLACE FUNCTION dbo.usp_workoutsession_getpersonalrecords(
    p_userid uuid,
    p_top integer DEFAULT 5
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    WITH ranked AS (
        SELECT
            wsl.exerciseid,
            e.name AS exercisename,
            dbo.ufn_exercise_loadmultiplier(e.equipmenttype, e.name) = 2 AS isperdumbbell,
            wsl.weightkg,
            wsl.reps,
            wsl.completedatutc,
            ROW_NUMBER() OVER (PARTITION BY wsl.exerciseid ORDER BY wsl.weightkg DESC, wsl.completedatutc ASC) AS rankinexercise
        FROM dbo.workoutsetlogs wsl
        INNER JOIN dbo.exercises e ON e.exerciseid = wsl.exerciseid
        WHERE wsl.userid = p_userid
    ),
    best AS (
        SELECT * FROM ranked WHERE rankinexercise = 1
    )
    SELECT
        b.exerciseid,
        b.exercisename,
        b.weightkg,
        b.reps,
        b.completedatutc,
        (
            SELECT MAX(prior.weightkg)
            FROM dbo.workoutsetlogs prior
            WHERE prior.userid = p_userid
              AND prior.exerciseid = b.exerciseid
              AND prior.completedatutc < b.completedatutc
        ) AS previousbestweightkg,
        b.isperdumbbell
    FROM best b
    ORDER BY b.completedatutc DESC
    LIMIT p_top;
    RETURN NEXT c1;
END $$;

-- Feeds the Progress screen: aggregate totals (result set 1) plus the raw
-- per-day statuses (result set 2) the service uses to build the heatmap and
-- the rule-based narrative text.
CREATE OR REPLACE FUNCTION dbo.usp_workoutsession_getrangesummary(
    p_userid uuid,
    p_fromdateutc date,
    p_todateutc date
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    c2 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT
        COUNT(CASE WHEN status = 'Completed' THEN 1 END)::int AS completedsessions,
        COUNT(*)::int AS scheduledsessions,
        COALESCE(SUM(CASE WHEN status = 'Completed' THEN tonnagekg END), 0) AS totaltonnagekg,
        COALESCE(AVG(CASE WHEN status = 'Completed' THEN rpescore END), 0) AS avgrpe
    FROM dbo.workoutsessions
    WHERE userid = p_userid AND scheduleddateutc BETWEEN p_fromdateutc AND p_todateutc;
    RETURN NEXT c1;

    OPEN c2 FOR
    SELECT scheduleddateutc, status, tonnagekg, rpescore
    FROM dbo.workoutsessions
    WHERE userid = p_userid AND scheduleddateutc BETWEEN p_fromdateutc AND p_todateutc
    ORDER BY scheduleddateutc;
    RETURN NEXT c2;
END $$;

-- Feeds Home's "View set history" button on a completed past day: every set
-- logged for that date's session, grouped by exercise (ordered by that
-- exercise's first logged set, so the list reads in the order the exercises
-- were actually worked, not alphabetically or by GUID) and by set number
-- within it.
CREATE OR REPLACE FUNCTION dbo.usp_workoutsession_getsetlogsbydate(
    p_userid uuid,
    p_scheduleddateutc date
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT
        wsl.exerciseid,
        e.name AS exercisename,
        wsl.setnumber,
        wsl.weightkg,
        wsl.reps,
        wsl.completedatutc
    FROM dbo.workoutsessions ws
    INNER JOIN dbo.workoutsetlogs wsl ON wsl.workoutsessionid = ws.workoutsessionid
    INNER JOIN dbo.exercises e ON e.exerciseid = wsl.exerciseid
    WHERE ws.userid = p_userid
      AND wsl.userid = p_userid
      AND ws.scheduleddateutc = p_scheduleddateutc
    ORDER BY MIN(wsl.completedatutc) OVER (PARTITION BY wsl.exerciseid), wsl.setnumber;
    RETURN NEXT c1;
END $$;

-- Powers the gated "Last time" card in the Active Workout Tracker: every set
-- logged for one exercise, across the most recent sessions it was trained in
-- (most recent session first, set number ascending within each). PRO/
-- Advanced entitlement is checked in TodayService, not here.
CREATE OR REPLACE FUNCTION dbo.usp_workoutsetlog_gethistorybyexercise(
    p_userid uuid,
    p_exerciseid uuid,
    p_top integer DEFAULT 5
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    WITH recentsessions AS (
        SELECT ws.workoutsessionid, ws.scheduleddateutc
        FROM dbo.workoutsessions ws
        WHERE ws.userid = p_userid
          AND EXISTS (
              SELECT 1 FROM dbo.workoutsetlogs wsl
              WHERE wsl.workoutsessionid = ws.workoutsessionid
                AND wsl.userid = p_userid
                AND wsl.exerciseid = p_exerciseid
          )
        ORDER BY ws.scheduleddateutc DESC
        LIMIT p_top
    )
    SELECT
        wsl.exerciseid,
        e.name AS exercisename,
        wsl.setnumber,
        wsl.weightkg,
        wsl.reps,
        wsl.completedatutc
    FROM recentsessions rs
    INNER JOIN dbo.workoutsetlogs wsl ON wsl.workoutsessionid = rs.workoutsessionid
    INNER JOIN dbo.exercises e ON e.exerciseid = wsl.exerciseid
    WHERE wsl.userid = p_userid
      AND wsl.exerciseid = p_exerciseid
    ORDER BY rs.scheduleddateutc DESC, wsl.setnumber;
    RETURN NEXT c1;
END $$;

-- Feeds the Progress screen's exercise picker: every exercise the user has
-- ever logged a set for, with how many sessions it was trained in and when
-- it was last trained (most recently trained first). PRO/Advanced
-- entitlement is checked in ProgressService, not here.
CREATE OR REPLACE FUNCTION dbo.usp_workoutsetlog_gettrackedexercises(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT
        wsl.exerciseid,
        e.name AS exercisename,
        COUNT(DISTINCT wsl.workoutsessionid)::int AS sessioncount,
        MAX(wsl.completedatutc) AS lasttrainedatutc,
        dbo.ufn_exercise_loadmultiplier(e.equipmenttype, e.name) = 2 AS isperdumbbell
    FROM dbo.workoutsetlogs wsl
    INNER JOIN dbo.exercises e ON e.exerciseid = wsl.exerciseid
    WHERE wsl.userid = p_userid
    GROUP BY wsl.exerciseid, e.name, e.equipmenttype
    ORDER BY MAX(wsl.completedatutc) DESC;
    RETURN NEXT c1;
END $$;

-- Feeds the Progress screen's per-exercise chart: one row per session the
-- exercise was trained in since p_fromdateutc (oldest first), reduced to the
-- heaviest set, the best Epley-estimated 1RM, and the session's total
-- volume/reps/sets for that exercise. Weights stay as logged (per dumbbell for
-- two-dumbbell moves); volume counts both dumbbells, like the session tonnage. PRO/Advanced entitlement is checked in
-- ProgressService, not here.
CREATE OR REPLACE FUNCTION dbo.usp_workoutsetlog_getexerciseprogress(
    p_userid uuid,
    p_exerciseid uuid,
    p_fromdateutc date
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    WITH sets AS (
        SELECT
            ws.workoutsessionid,
            ws.scheduleddateutc,
            wsl.weightkg,
            wsl.reps,
            dbo.ufn_exercise_loadmultiplier(e.equipmenttype, e.name) AS loadmultiplier,
            -- Epley; a single rep already *is* the 1RM.
            CASE WHEN wsl.reps = 1 THEN wsl.weightkg
                 ELSE wsl.weightkg * (1 + wsl.reps / 30.0) END AS estimatedonermkg,
            ROW_NUMBER() OVER (PARTITION BY ws.workoutsessionid
                               ORDER BY wsl.weightkg DESC, wsl.reps DESC) AS rankinsession
        FROM dbo.workoutsetlogs wsl
        INNER JOIN dbo.workoutsessions ws ON ws.workoutsessionid = wsl.workoutsessionid
        INNER JOIN dbo.exercises e ON e.exerciseid = wsl.exerciseid
        WHERE wsl.userid = p_userid
          AND ws.userid = p_userid
          AND wsl.exerciseid = p_exerciseid
          AND ws.scheduleddateutc >= p_fromdateutc
    )
    SELECT
        s.scheduleddateutc,
        MAX(CASE WHEN s.rankinsession = 1 THEN s.weightkg END) AS topweightkg,
        MAX(CASE WHEN s.rankinsession = 1 THEN s.reps END)::smallint AS topsetreps,
        MAX(s.estimatedonermkg)::numeric(8,2) AS estimatedonermkg,
        SUM(s.weightkg * s.reps * s.loadmultiplier)::numeric(12,2) AS totalvolumekg,
        SUM(s.reps::int)::int AS totalreps,
        COUNT(*)::int AS setcount
    FROM sets s
    GROUP BY s.workoutsessionid, s.scheduleddateutc
    ORDER BY s.scheduleddateutc ASC;
    RETURN NEXT c1;
END $$;

-- "Still working out" heartbeat, called by the Active Workout Tracker while a
-- session is open. Records the session's start the first time it is seen and
-- refreshes LastActivityAtUtc on every ping. The notification publisher reads
-- the resulting idle gap to decide when to nudge "log your sets" - it is
-- intentionally best-effort and a no-op if there is no open session.
-- p_hascompletedsets stamps FirstSetCompletedAtUtc, which is what pins today's
-- session to its split day in usp_WorkoutSession_GetTodayScheduled.
CREATE OR REPLACE FUNCTION dbo.usp_workoutsession_heartbeat(
    p_userid uuid,
    p_workoutsessionid uuid DEFAULT NULL,
    p_atutc timestamp(3) DEFAULT NULL,
    p_hascompletedsets boolean DEFAULT false
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_sessionid uuid := p_workoutsessionid;
BEGIN
    IF v_sessionid IS NULL THEN
        SELECT workoutsessionid INTO v_sessionid
        FROM dbo.workoutsessions
        WHERE userid = p_userid
          AND completedatutc IS NULL
          AND scheduleddateutc = p_atutc::date
        ORDER BY createdatutc DESC
        LIMIT 1;
    END IF;

    IF v_sessionid IS NULL THEN
        RETURN;
    END IF;

    UPDATE dbo.workoutsessions
    SET startedatutc           = COALESCE(startedatutc, p_atutc),
        lastactivityatutc      = p_atutc,
        firstsetcompletedatutc = CASE WHEN p_hascompletedsets
                                      THEN COALESCE(firstsetcompletedatutc, p_atutc)
                                      ELSE firstsetcompletedatutc END
    WHERE workoutsessionid = v_sessionid
      AND userid = p_userid
      AND completedatutc IS NULL;
END $$;
