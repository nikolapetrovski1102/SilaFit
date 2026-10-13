-- Claims one of today's AI food scans for p_userid, or reports that the
-- allowance is spent. "Today" is the user's local day, resolved by the caller
-- into p_daystartutc. The per-user advisory lock serialises concurrent
-- reservations, so two scans started at the same moment can't both read
-- "2 used" and both go through.
CREATE OR REPLACE FUNCTION dbo.usp_foodscan_tryreserve(
    p_userid uuid,
    p_daystartutc timestamp(3),
    p_dailylimit integer
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_used integer;
    v_foodscanid bigint;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended('foodscan:' || p_userid::text, 0));

    SELECT COUNT(*) INTO v_used
    FROM dbo.foodscans
    WHERE userid = p_userid
      AND scannedatutc >= p_daystartutc;

    IF v_used >= p_dailylimit THEN
        OPEN c1 FOR SELECT false AS allowed, v_used AS usedtoday, NULL::bigint AS foodscanid;
        RETURN NEXT c1;
        RETURN;
    END IF;

    INSERT INTO dbo.foodscans (userid) VALUES (p_userid)
    RETURNING foodscanid INTO v_foodscanid;

    OPEN c1 FOR SELECT true AS allowed, v_used + 1 AS usedtoday, v_foodscanid AS foodscanid;
    RETURN NEXT c1;
END $$;

-- Gives a reserved scan back - the AI call behind it failed, so it shouldn't
-- count against the day.
CREATE OR REPLACE FUNCTION dbo.usp_foodscan_release(
    p_userid uuid,
    p_foodscanid bigint
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM dbo.foodscans
    WHERE foodscanid = p_foodscanid
      AND userid = p_userid;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_foodscan_countsince(
    p_userid uuid,
    p_daystartutc timestamp(3)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT COUNT(*)::int AS usedtoday
    FROM dbo.foodscans
    WHERE userid = p_userid
      AND scannedatutc >= p_daystartutc;
    RETURN NEXT c1;
END $$;
