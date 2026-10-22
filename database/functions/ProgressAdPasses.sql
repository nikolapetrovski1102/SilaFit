-- Grants a Free account a Progress pass for watching a rewarded video ad.
-- Always returns one row whose Status is Ok or LimitReached; ExpiresAtUtc is
-- the new pass's expiry for Ok, or when the oldest pass in the window drops
-- out (the earliest a new one can be granted) for LimitReached.
CREATE OR REPLACE FUNCTION dbo.usp_progressadpass_grant(
    p_userid uuid,
    p_validminutes integer,
    p_dailylimit integer
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_now timestamp(3) := dbo.sysutcdatetime();
    v_count integer;
    v_status text;
    v_expires timestamp(3);
BEGIN
    -- Serialises one user's grants so two quick taps can't both slip under the cap.
    PERFORM 1 FROM dbo.users WHERE userid = p_userid FOR UPDATE;

    SELECT count(*), min(grantedatutc) + interval '1 day'
    INTO v_count, v_expires
    FROM dbo.progressadpasses
    WHERE userid = p_userid
      AND grantedatutc > v_now - interval '1 day';

    IF v_count >= p_dailylimit THEN
        v_status := 'LimitReached';
    ELSE
        v_expires := v_now + make_interval(mins => p_validminutes);
        INSERT INTO dbo.progressadpasses (userid, grantedatutc, expiresatutc)
        VALUES (p_userid, v_now, v_expires);
        v_status := 'Ok';
    END IF;

    OPEN c1 FOR
    SELECT v_status AS status,
           v_expires AS expiresatutc;
    RETURN NEXT c1;
END $$;

-- One row, HasActivePass: whether the user holds an unexpired Progress pass.
CREATE OR REPLACE FUNCTION dbo.usp_progressadpass_hasactive(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT EXISTS (
        SELECT 1
        FROM dbo.progressadpasses
        WHERE userid = p_userid
          AND expiresatutc > dbo.sysutcdatetime()
    ) AS hasactivepass;
    RETURN NEXT c1;
END $$;

-- Ends the user's unexpired Progress passes now - the app calls this when the
-- user leaves the Progress screen, so a pass covers one look, not 15 minutes.
-- The rows stay, still counting toward the daily cap.
CREATE OR REPLACE FUNCTION dbo.usp_progressadpass_end(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.progressadpasses
    SET expiresatutc = dbo.sysutcdatetime()
    WHERE userid = p_userid
      AND expiresatutc > dbo.sysutcdatetime();
END $$;
