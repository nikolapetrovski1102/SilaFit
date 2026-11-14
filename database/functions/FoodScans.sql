-- Claims one food scan of p_kind ('meal' = AI meal photo, 'barcode' = a
-- Free-tier trial barcode lookup) for p_userid, or reports that the allowance
-- is spent.
--
-- Paid (p_istrial = false): at most p_dailylimit scans of this kind since
-- p_daystartutc (the user's local midnight, resolved by the caller).
-- Free (p_istrial = true): at most p_triallimit trial scans of this kind ever.
--
-- The per-user advisory lock serialises concurrent reservations, so two scans
-- started at the same moment can't both read "2 used" and both go through.
CREATE OR REPLACE FUNCTION dbo.usp_foodscan_tryreserve(
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
    v_foodscanid bigint;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended('foodscan:' || p_userid::text, 0));

    IF p_istrial THEN
        SELECT COUNT(*) INTO v_used
        FROM dbo.foodscans
        WHERE userid = p_userid AND kind = p_kind AND istrial;
        v_limit := p_triallimit;
    ELSE
        SELECT COUNT(*) INTO v_used
        FROM dbo.foodscans
        WHERE userid = p_userid AND kind = p_kind AND NOT istrial AND scannedatutc >= p_daystartutc;
        v_limit := p_dailylimit;
    END IF;

    IF v_used >= v_limit THEN
        OPEN c1 FOR SELECT false AS allowed, v_used AS used, NULL::bigint AS foodscanid;
        RETURN NEXT c1;
        RETURN;
    END IF;

    INSERT INTO dbo.foodscans (userid, kind, istrial) VALUES (p_userid, p_kind, p_istrial)
    RETURNING foodscanid INTO v_foodscanid;

    OPEN c1 FOR SELECT true AS allowed, v_used + 1 AS used, v_foodscanid AS foodscanid;
    RETURN NEXT c1;
END $$;

-- Gives a reserved scan back - the AI call behind it failed, so it shouldn't
-- count.
CREATE OR REPLACE FUNCTION dbo.usp_foodscan_release(
    p_userid uuid,
    p_foodscanid bigint
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM dbo.foodscans
    WHERE foodscanid = p_foodscanid
      AND userid = p_userid;
END $$;

-- Today's AI meal scans, plus the lifetime Free-tier barcode lookups.
CREATE OR REPLACE FUNCTION dbo.usp_foodscan_usage(
    p_userid uuid,
    p_daystartutc timestamp(3)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT
        COUNT(*) FILTER (WHERE kind = 'meal' AND NOT istrial AND scannedatutc >= p_daystartutc)::int AS mealtoday,
        COUNT(*) FILTER (WHERE kind = 'barcode' AND istrial)::int AS barcodetrialused
    FROM dbo.foodscans
    WHERE userid = p_userid;
    RETURN NEXT c1;
END $$;
