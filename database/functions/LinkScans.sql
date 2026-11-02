-- Claims one link scan of p_kind for p_userid, or reports why not.
--
-- Paid (p_istrial = false): at most p_dailylimit scans of this kind since
-- p_daystartutc (the user's local midnight, resolved by the caller).
-- Free (p_istrial = true): at most p_triallimit trial scans ever, any kind.
--
-- The per-user advisory lock serialises concurrent reservations, so two scans
-- started at once can't both read "2 used" and both go through.
CREATE OR REPLACE FUNCTION dbo.usp_linkscan_tryreserve(
    p_userid uuid,
    p_kind varchar(10),
    p_istrial boolean,
    p_daystartutc timestamp(3),
    p_dailylimit integer,
    p_triallimit integer
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_used integer;
    v_limit integer;
    v_linkscanid bigint;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended('linkscan:' || p_userid::text, 0));

    IF p_istrial THEN
        SELECT COUNT(*) INTO v_used
        FROM dbo.linkscans
        WHERE userid = p_userid AND istrial;
        v_limit := p_triallimit;
    ELSE
        SELECT COUNT(*) INTO v_used
        FROM dbo.linkscans
        WHERE userid = p_userid AND kind = p_kind AND scannedatutc >= p_daystartutc;
        v_limit := p_dailylimit;
    END IF;

    IF v_used >= v_limit THEN
        OPEN c1 FOR SELECT false AS allowed, v_used AS used, NULL::bigint AS linkscanid;
        RETURN NEXT c1;
        RETURN;
    END IF;

    INSERT INTO dbo.linkscans (userid, kind, istrial) VALUES (p_userid, p_kind, p_istrial)
    RETURNING linkscanid INTO v_linkscanid;

    OPEN c1 FOR SELECT true AS allowed, v_used + 1 AS used, v_linkscanid AS linkscanid;
    RETURN NEXT c1;
END $$;

-- Gives a reserved scan back - the work behind it failed, so it shouldn't count.
CREATE OR REPLACE FUNCTION dbo.usp_linkscan_release(
    p_userid uuid,
    p_linkscanid bigint
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM dbo.linkscans
    WHERE linkscanid = p_linkscanid
      AND userid = p_userid;
END $$;

-- Today's paid scans per kind, plus the lifetime trial count.
CREATE OR REPLACE FUNCTION dbo.usp_linkscan_usage(
    p_userid uuid,
    p_daystartutc timestamp(3)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT
        COUNT(*) FILTER (WHERE kind = 'workout' AND NOT istrial AND scannedatutc >= p_daystartutc)::int AS workouttoday,
        COUNT(*) FILTER (WHERE kind = 'meal' AND NOT istrial AND scannedatutc >= p_daystartutc)::int AS mealtoday,
        COUNT(*) FILTER (WHERE istrial)::int AS trialused
    FROM dbo.linkscans
    WHERE userid = p_userid;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_linkscancache_get(
    p_provider varchar(20),
    p_videoid varchar(64)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT resultjson
    FROM dbo.linkscancache
    WHERE provider = p_provider AND videoid = p_videoid;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_linkscancache_put(
    p_provider varchar(20),
    p_videoid varchar(64),
    p_resultjson text
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO dbo.linkscancache (provider, videoid, resultjson)
    VALUES (p_provider, p_videoid, p_resultjson)
    ON CONFLICT (provider, videoid) DO NOTHING;
END $$;
