-- The app's split library.
--
-- Visibility rules live here, not in the API, so there is exactly one predicate
-- deciding what a normal user may see and no endpoint can accidentally bypass it:
--
--   * system/shipped splits          - always visible (public catalogue)
--   * Visibility = 'Public'          - a trainer's split shared with everyone
--   * a SplitAssignments row for the caller - 'Shared'/'Private' split handed to
--     this specific user. Guests (p_userid NULL) only ever see the first two.
--
-- p_userid is optional because the library is browseable by guests.
--
-- LIMIT is a safety valve, not paging: the catalogue is curated content, but an
-- admin/trainer could in principle create unbounded public splits and this list is
-- anonymous, so the response is capped rather than allowed to grow without bound.
CREATE OR REPLACE FUNCTION dbo.usp_splits_getall(
    p_userid uuid DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT s.splitid,
           s.name,
           s.category,
           s.level,
           s.durationdays,
           s.description,
           s.heroimageurl,
           s.issystemdefault,
           s.sortorder,
           s.recommendedgoal,
           s.visibility,
           s.daysperweek,
           s.programdurationweeks,
           s.minsessionminutes,
           s.maxsessionminutes,
           s.equipmentrequired,
           s.targetgender,
           s.workouttypelabel,
           s.sourcecategoriesjson,
           s.owneruserid,
           s.isaigenerated,
           s.aikeptatutc,
           -- Average training-day length, surfaced so the recommender can fit a
           -- user's session-duration answer. Rest days are excluded so a split
           -- with recovery days booked still reports a realistic session.
           COALESCE((SELECT trunc(AVG(d.estimatedminutes))::int
                     FROM dbo.splitdays d
                     WHERE d.splitid = s.splitid
                       AND NOT d.isrestday), 0) AS avgsessionminutes
    FROM dbo.workoutsplits s
    WHERE s.issystemdefault
       OR s.visibility = 'Public'
       OR (p_userid IS NOT NULL AND s.owneruserid = p_userid)
       OR (p_userid IS NOT NULL
           AND EXISTS (SELECT 1
                       FROM dbo.splitassignments a
                       WHERE a.splitid = s.splitid
                         AND a.userid = p_userid))
    ORDER BY s.sortorder
    LIMIT 2500;
    RETURN NEXT c1;
END $$;

-- Result set 1: split header. Result set 2: its days. Result set 3: each
-- day's target exercises.
--
-- Detail is behind the same visibility predicate as the list: a user who
-- guesses a SplitId must not be able to read a private or unassigned split.
-- All three result sets are always emitted (empty when invisible) so the
-- provider's reader can advance through them unconditionally; a null header
-- is what the service turns into "not found".
CREATE OR REPLACE FUNCTION dbo.usp_splits_getdetail(
    p_splitid uuid,
    p_userid uuid DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    c2 refcursor;
    c3 refcursor;
    v_visible boolean;
BEGIN
    v_visible := EXISTS (
        SELECT 1
        FROM dbo.workoutsplits s
        WHERE s.splitid = p_splitid
          AND (s.issystemdefault
               OR s.visibility = 'Public'
               OR (p_userid IS NOT NULL AND s.owneruserid = p_userid)
               OR (p_userid IS NOT NULL
                   AND EXISTS (SELECT 1
                               FROM dbo.splitassignments a
                               WHERE a.splitid = s.splitid
                                 AND a.userid = p_userid))));

    OPEN c1 FOR
    SELECT splitid, name, category, level, durationdays, description, heroimageurl, issystemdefault, sortorder, recommendedgoal, visibility,
           daysperweek, programdurationweeks, minsessionminutes, maxsessionminutes,
           equipmentrequired, targetgender, workouttypelabel, sourcecategoriesjson, owneruserid, isaigenerated, aikeptatutc,
           COALESCE((SELECT trunc(AVG(d.estimatedminutes))::int
                     FROM dbo.splitdays d
                     WHERE d.splitid = p_splitid
                       AND NOT d.isrestday), 0) AS avgsessionminutes
    FROM dbo.workoutsplits
    WHERE splitid = p_splitid
      AND v_visible;
    RETURN NEXT c1;

    OPEN c2 FOR
    SELECT splitdayid, dayindex, title, focuslabel, estimatedminutes, isrestday
    FROM dbo.splitdays
    WHERE splitid = p_splitid
      AND v_visible
    ORDER BY dayindex;
    RETURN NEXT c2;

    OPEN c3 FOR
    SELECT sd.splitdayid, sde.splitdayexerciseid, e.exerciseid, e.name, e.musclegroup, sde.sortorder, sde.targetsets, sde.targetrepslow, sde.targetrepshigh
    FROM dbo.splitdays sd
    INNER JOIN dbo.splitdayexercises sde ON sde.splitdayid = sd.splitdayid
    INNER JOIN dbo.exercises e ON e.exerciseid = sde.exerciseid
    WHERE sd.splitid = p_splitid
      AND v_visible
    ORDER BY sd.dayindex, sde.sortorder;
    RETURN NEXT c3;
END $$;

-- p_isautoassigned defaults to false (a user's own pick via POST /api/splits/activate).
-- The recommender passes true explicitly, so a later re-check
-- (AutoAssignRecommendedAsync) can tell its own pick apart from one the user
-- made deliberately and never overwrite the latter.
CREATE OR REPLACE FUNCTION dbo.usp_useractivesplit_set(
    p_userid uuid,
    p_splitid uuid,
    p_isautoassigned boolean DEFAULT false
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    -- Same visibility predicate as usp_Splits_GetDetail: a Shared/Private split
    -- the caller was never assigned can't be activated just by knowing its id.
    -- No row back means "not found" to SplitService.ActivateAsync.
    IF NOT EXISTS (SELECT 1
                   FROM dbo.workoutsplits s
                   WHERE s.splitid = p_splitid
                     AND (s.issystemdefault
                          OR s.visibility = 'Public'
                          OR s.owneruserid = p_userid
                          OR EXISTS (SELECT 1
                                     FROM dbo.splitassignments a
                                     WHERE a.splitid = s.splitid
                                       AND a.userid = p_userid))) THEN
        -- Still emit the result shape so the reader sees an empty set, not none.
        OPEN c1 FOR SELECT userid, splitid, activatedatutc, isautoassigned FROM dbo.useractivesplits WHERE false;
        RETURN NEXT c1;
        RETURN;
    END IF;

    INSERT INTO dbo.useractivesplits (userid, splitid, activatedatutc, isautoassigned)
    VALUES (p_userid, p_splitid, dbo.sysutcdatetime(), p_isautoassigned)
    ON CONFLICT (userid) DO UPDATE SET
        splitid = EXCLUDED.splitid, activatedatutc = dbo.sysutcdatetime(), isautoassigned = EXCLUDED.isautoassigned;

    OPEN c1 FOR SELECT userid, splitid, activatedatutc, isautoassigned FROM dbo.useractivesplits WHERE userid = p_userid;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_useractivesplit_get(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT uas.userid, uas.splitid, uas.activatedatutc, uas.isautoassigned, ws.name, ws.durationdays
    FROM dbo.useractivesplits uas
    INNER JOIN dbo.workoutsplits ws ON ws.splitid = uas.splitid
    WHERE uas.userid = p_userid;
    RETURN NEXT c1;
END $$;
