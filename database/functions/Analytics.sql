-- Feeds AnalyticsService's monthly AI report: every real number the prompt
-- template's {{Placeholder}} tokens get substituted with, as a single flat
-- row. CurrentStreakDays/WeeklyCompliancePercent come from the same
-- dbo.ufn_streak_getstatus as usp_Streak_GetStatus (current-state, not
-- scoped to the requested month - a mid-month streak read is still
-- meaningful context for the AI).
--
-- StartWeightKg/EndWeightKg/AvgCaloriesLogged are NOT computed here:
-- BodyweightLogs.WeightKg and MealLogs.CaloriesKcal are AES-256-GCM
-- ciphertext (Silen.Common.Helpers.FieldCipher) and can't be aggregated in
-- SQL. AnalyticsProvider fills those three fields in C# instead, via
-- IBodyweightProvider.GetInRangeAsync / IMealPlanningProvider.GetCaloriesInRangeAsync.
-- LoggedMealDays stays here since COUNT(DISTINCT LogDateUtc) never touches
-- an encrypted column.
CREATE OR REPLACE FUNCTION dbo.usp_analytics_getmonthlysnapshot(
    p_userid uuid,
    p_fromdateutc date,
    p_todateutc date
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_today date := dbo.sysutcdatetime()::date;
BEGIN
    OPEN c1 FOR
    SELECT
        COALESCE(u.displayname, 'Athlete') AS displayname,

        COALESCE(ws.completedsessions, 0) AS completedsessions,
        COALESCE(ws.scheduledsessions, 0) AS scheduledsessions,
        COALESCE(ws.totaltonnagekg, 0) AS totaltonnagekg,
        COALESCE(ws.avgrpe, 0) AS avgrpe,

        st.currentstreakdays,
        st.weeklycompliancepercent,

        COALESCE(ml.loggedmealdays, 0) AS loggedmealdays,
        (p_todateutc - p_fromdateutc) + 1 AS totaldaysinrange,
        nt.targetcalories

    FROM dbo.users u
    CROSS JOIN LATERAL dbo.ufn_streak_getstatus(p_userid, v_today) st
    LEFT JOIN LATERAL (
        SELECT
            COUNT(CASE WHEN status = 'Completed' THEN 1 END)::int AS completedsessions,
            COUNT(*)::int AS scheduledsessions,
            COALESCE(SUM(CASE WHEN status = 'Completed' THEN tonnagekg END), 0) AS totaltonnagekg,
            COALESCE(AVG(CASE WHEN status = 'Completed' THEN rpescore END), 0) AS avgrpe
        FROM dbo.workoutsessions
        WHERE userid = p_userid AND scheduleddateutc BETWEEN p_fromdateutc AND p_todateutc
    ) ws ON true
    LEFT JOIN LATERAL (
        SELECT COUNT(DISTINCT logdateutc)::int AS loggedmealdays
        FROM dbo.meallogs
        WHERE userid = p_userid AND status = 'Logged' AND logdateutc BETWEEN p_fromdateutc AND p_todateutc
    ) ml ON true
    LEFT JOIN dbo.usernutritiontargets nt ON nt.userid = p_userid
    WHERE u.userid = p_userid;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_aiprompttemplate_getactive(
    p_templatekey varchar(50)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT prompttemplateid, templatekey, systemprompt, userprompttemplate, model, isactive, updatedatutc
    FROM dbo.aiprompttemplates
    WHERE templatekey = p_templatekey AND isactive
    ORDER BY updatedatutc DESC
    LIMIT 1;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_analytics_getcachedreport(
    p_userid uuid,
    p_reportyear smallint,
    p_reportmonth smallint
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT reportid, userid, reportyear, reportmonth, snapshotjson, resultjson, generatedatutc
    FROM dbo.monthlyanalyticsreports
    WHERE userid = p_userid AND reportyear = p_reportyear AND reportmonth = p_reportmonth;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_analytics_upsertreport(
    p_userid uuid,
    p_reportyear smallint,
    p_reportmonth smallint,
    p_snapshotjson text,
    p_resultjson text
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    INSERT INTO dbo.monthlyanalyticsreports (userid, reportyear, reportmonth, snapshotjson, resultjson)
    VALUES (p_userid, p_reportyear, p_reportmonth, p_snapshotjson, p_resultjson)
    ON CONFLICT (userid, reportyear, reportmonth) DO UPDATE SET
        snapshotjson = EXCLUDED.snapshotjson, resultjson = EXCLUDED.resultjson, generatedatutc = dbo.sysutcdatetime();

    OPEN c1 FOR
    SELECT reportid, userid, reportyear, reportmonth, snapshotjson, resultjson, generatedatutc
    FROM dbo.monthlyanalyticsreports
    WHERE userid = p_userid AND reportyear = p_reportyear AND reportmonth = p_reportmonth;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_analytics_getcachedweeklyreport(
    p_userid uuid,
    p_reportyear smallint,
    p_reportweek smallint
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT reportid, userid, reportyear, reportweek, snapshotjson, resultjson, generatedatutc
    FROM dbo.weeklyanalyticsreports
    WHERE userid = p_userid AND reportyear = p_reportyear AND reportweek = p_reportweek;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_analytics_upsertweeklyreport(
    p_userid uuid,
    p_reportyear smallint,
    p_reportweek smallint,
    p_snapshotjson text,
    p_resultjson text
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    INSERT INTO dbo.weeklyanalyticsreports (userid, reportyear, reportweek, snapshotjson, resultjson)
    VALUES (p_userid, p_reportyear, p_reportweek, p_snapshotjson, p_resultjson)
    ON CONFLICT (userid, reportyear, reportweek) DO UPDATE SET
        snapshotjson = EXCLUDED.snapshotjson, resultjson = EXCLUDED.resultjson, generatedatutc = dbo.sysutcdatetime();

    OPEN c1 FOR
    SELECT reportid, userid, reportyear, reportweek, snapshotjson, resultjson, generatedatutc
    FROM dbo.weeklyanalyticsreports
    WHERE userid = p_userid AND reportyear = p_reportyear AND reportweek = p_reportweek;
    RETURN NEXT c1;
END $$;

-- Recap evidence: only past missed training days and real completed sets.
-- PR includes history through report end, never future records.
CREATE OR REPLACE FUNCTION dbo.usp_analytics_getmonthlyexercisehistory(
    p_userid uuid,
    p_fromdateutc date,
    p_todateutc date
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    c2 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT COUNT(DISTINCT ws.scheduleddateutc)::int AS missedworkoutdays
    FROM dbo.workoutsessions ws
    LEFT JOIN dbo.splitdays sd ON sd.splitdayid = ws.splitdayid
    WHERE ws.userid = p_userid
      AND ws.scheduleddateutc BETWEEN p_fromdateutc AND p_todateutc
      AND ws.scheduleddateutc < dbo.sysutcdatetime()::date
      AND ws.status IN ('Scheduled', 'Missed')
      AND NOT COALESCE(sd.isrestday, false);
    RETURN NEXT c1;

    OPEN c2 FOR
    WITH rankedsets AS (
        SELECT sl.exerciseid, sl.workoutsessionid, sl.weightkg, sl.reps,
               sl.completedatutc, ws.rpescore,
               ROW_NUMBER() OVER (
                   PARTITION BY sl.workoutsessionid, sl.exerciseid
                   ORDER BY sl.weightkg DESC, sl.reps DESC, sl.setnumber, sl.workoutsetlogid
               ) AS setrank
        FROM dbo.workoutsetlogs sl
        INNER JOIN dbo.workoutsessions ws ON ws.workoutsessionid = sl.workoutsessionid AND ws.userid = sl.userid
        WHERE sl.userid = p_userid AND ws.status = 'Completed'
          AND sl.completedatutc >= p_fromdateutc
          AND sl.completedatutc < p_todateutc + 1
    )
    SELECT r.exerciseid, e.name AS exercisename, r.weightkg, r.reps,
           r.completedatutc, r.rpescore, pr.recordweightkg
    FROM rankedsets r
    INNER JOIN dbo.exercises e ON e.exerciseid = r.exerciseid
    CROSS JOIN LATERAL (
        SELECT MAX(h.weightkg) AS recordweightkg
        FROM dbo.workoutsetlogs h
        INNER JOIN dbo.workoutsessions hs ON hs.workoutsessionid = h.workoutsessionid AND hs.userid = h.userid
        WHERE h.userid = p_userid AND h.exerciseid = r.exerciseid
          AND hs.status = 'Completed'
          AND h.completedatutc < p_todateutc + 1
    ) pr
    WHERE r.setrank = 1
    ORDER BY e.name, r.exerciseid, r.completedatutc, r.workoutsessionid;
    RETURN NEXT c2;
END $$;
