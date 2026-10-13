-- Current streak + this week's compliance for one user, shared by
-- usp_Streak_GetStatus (Home's streak badge) and
-- usp_Analytics_GetMonthlySnapshot so the two can't drift apart.
--
-- A day "keeps" the streak when it was either trained (Completed /
-- ActiveRest) or a rest day in the user's split. Rest days are resolved the
-- same way Home's day strip does it (resolveSplitDay in day_preview.dart):
-- from the session's own SplitDay when a session row exists, otherwise from
-- the active split's rotation - rest days usually never get a session row at
-- all (implicit rest positions past the last SplitDay) or keep the default
-- 'Scheduled' status, since nothing ever flips a real session to ActiveRest.
-- The rotation is only trusted from the split's activation date on; before
-- that the user was on some other split we no longer know about.
--
-- Today is a grace day: an unfinished today doesn't break the streak (it
-- would otherwise read 0 every morning until the workout is logged), it just
-- doesn't count yet. The break search is therefore strictly before p_today.
--
-- Looks back up to 999 days, so long streaks aren't capped by the window.
-- Weeks are Monday-anchored (date_trunc('week') is ISO, Monday first).
CREATE OR REPLACE FUNCTION dbo.ufn_streak_getstatus(
    p_userid uuid,
    p_today date
) RETURNS TABLE (currentstreakdays integer, weeklycompliancepercent integer)
LANGUAGE sql STABLE AS $$
    WITH activesplit AS (
        -- Same Monday-anchored, whole-weeks rotation as
        -- usp_WorkoutSession_GetTodayScheduled (v_cyclelength there).
        SELECT uas.splitid,
               uas.activatedatutc::date AS activateddate,
               date_trunc('week', uas.activatedatutc::date)::date AS anchordate,
               7 * ((CASE WHEN COALESCE(md.maxdayindex, 0) > ws.durationdays THEN md.maxdayindex
                          ELSE ws.durationdays::int END + 6) / 7) AS cyclelength
        FROM dbo.useractivesplits uas
        INNER JOIN dbo.workoutsplits ws ON ws.splitid = uas.splitid
        LEFT JOIN LATERAL (SELECT MAX(sd.dayindex::int) AS maxdayindex
                           FROM dbo.splitdays sd WHERE sd.splitid = uas.splitid) md ON true
        WHERE uas.userid = p_userid AND ws.durationdays > 0
    ),
    rotationdays AS (
        -- Slot = stored DayIndex - 1, so a numbering gap (Day 1, 2, 4) rests
        -- on the missing day - see usp_WorkoutSession_GetTodayScheduled.
        SELECT sd.isrestday,
               sd.dayindex::int - 1 AS cyclepos
        FROM dbo.splitdays sd
        INNER JOIN activesplit a ON a.splitid = sd.splitid
    ),
    calendar AS (
        SELECT p_today - n AS calendardate
        FROM generate_series(0, 999) AS g(n)
    ),
    daystatus AS (
        SELECT c.calendardate,
               CASE
                   WHEN EXISTS (SELECT 1 FROM dbo.workoutsessions ws
                                WHERE ws.userid = p_userid AND ws.scheduleddateutc = c.calendardate
                                  AND ws.status IN ('Completed', 'ActiveRest'))
                       THEN 1
                   WHEN EXISTS (SELECT 1 FROM dbo.workoutsessions ws
                                INNER JOIN dbo.splitdays sd ON sd.splitdayid = ws.splitdayid
                                WHERE ws.userid = p_userid AND ws.scheduleddateutc = c.calendardate
                                  AND sd.isrestday)
                       THEN 1
                   -- No session tied to a split day: fall back to the rotation.
                   -- A position with no non-rest SplitDay is a rest day (either
                   -- flagged IsRestDay, a gap in the numbering, or an implicit
                   -- pad past the last day).
                   WHEN NOT EXISTS (SELECT 1 FROM dbo.workoutsessions ws
                                    WHERE ws.userid = p_userid AND ws.scheduleddateutc = c.calendardate
                                      AND ws.splitdayid IS NOT NULL)
                        AND EXISTS (SELECT 1 FROM activesplit a
                                    WHERE c.calendardate >= a.activateddate
                                      AND NOT EXISTS (
                                          SELECT 1 FROM rotationdays r
                                          WHERE NOT r.isrestday
                                            AND r.cyclepos = (((c.calendardate - a.anchordate) % a.cyclelength)
                                                              + a.cyclelength) % a.cyclelength))
                       THEN 1
                   ELSE 0
               END AS iskept
        FROM calendar c
    )
    SELECT
        (SELECT COUNT(*)::int FROM daystatus
         WHERE iskept = 1
           AND calendardate > COALESCE((SELECT MAX(calendardate) FROM daystatus
                                        WHERE iskept = 0 AND calendardate < p_today),
                                       DATE '0001-01-01')) AS currentstreakdays,
        COALESCE((SELECT round(100.0 * SUM(iskept) / 7.0, 0)::int
                  FROM daystatus
                  WHERE calendardate >= date_trunc('week', p_today)::date), 0)
            AS weeklycompliancepercent;
$$;

-- Result set 1: current streak + this week's compliance percentage (see
-- dbo.ufn_Streak_GetStatus for what counts).
-- Result set 2: Monday..Sunday of the current week with each day's session
-- status, for the "consistency strip" UI.
CREATE OR REPLACE FUNCTION dbo.usp_streak_getstatus(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    c2 refcursor;
    v_today date := dbo.sysutcdatetime()::date;
    v_weekstart date := date_trunc('week', v_today)::date;
BEGIN
    OPEN c1 FOR
    SELECT currentstreakdays, weeklycompliancepercent
    FROM dbo.ufn_streak_getstatus(p_userid, v_today);
    RETURN NEXT c1;

    OPEN c2 FOR
    SELECT
        w.calendardate AS sessiondate,
        ws.status AS sessionstatus
    FROM (SELECT v_weekstart + n AS calendardate FROM generate_series(0, 6) AS g(n)) w
    LEFT JOIN dbo.workoutsessions ws
           ON ws.userid = p_userid AND ws.scheduleddateutc = w.calendardate
    ORDER BY w.calendardate;
    RETURN NEXT c2;
END $$;
