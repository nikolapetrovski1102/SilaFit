-- WeightKg is AES-256-GCM ciphertext (Silen.Common.Helpers.FieldCipher),
-- encrypted/decrypted at the BodyweightProvider layer.

-- Returns the two most recent entries so the caller can compute the delta
-- without a second round-trip.
CREATE OR REPLACE FUNCTION dbo.usp_bodyweight_log(
    p_userid uuid,
    p_weightkg bytea,
    p_bodyweightlogid uuid DEFAULT NULL,
    p_loggedatutc timestamp(3) DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_loggedatutc timestamp(3) := COALESCE(p_loggedatutc, dbo.sysutcdatetime());
    v_inserted integer;
BEGIN
    -- The client id makes a replay harmless: an entry logged offline and
    -- re-sent after a dropped response is stored once, not twice.
    INSERT INTO dbo.bodyweightlogs (bodyweightlogid, userid, weightkg, loggedatutc)
    VALUES (COALESCE(p_bodyweightlogid, uuidv7()), p_userid, p_weightkg, v_loggedatutc)
    ON CONFLICT (bodyweightlogid) DO NOTHING;
    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    -- BodyweightLogs is the chronological source of truth. Keep the profile's
    -- denormalized weight aligned with the value the user just entered so BMI,
    -- recommendations and automatically derived nutrition targets do not keep
    -- using the older onboarding weight - unless this was a late upload that
    -- a newer entry has already superseded.
    IF v_inserted > 0 AND NOT EXISTS (
        SELECT 1 FROM dbo.bodyweightlogs
        WHERE userid = p_userid AND loggedatutc > v_loggedatutc
    ) THEN
        UPDATE dbo.userprofiles
        SET weightkg = p_weightkg,
            updatedatutc = dbo.sysutcdatetime()
        WHERE userid = p_userid;
    END IF;

    OPEN c1 FOR
    SELECT bodyweightlogid, weightkg, loggedatutc
    FROM dbo.bodyweightlogs
    WHERE userid = p_userid
    ORDER BY loggedatutc DESC, bodyweightlogid DESC
    LIMIT 2;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_bodyweight_getlatest(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT bodyweightlogid, weightkg, loggedatutc
    FROM dbo.bodyweightlogs
    WHERE userid = p_userid
    ORDER BY loggedatutc DESC, bodyweightlogid DESC
    LIMIT 2;
    RETURN NEXT c1;
END $$;

-- Feeds AnalyticsProvider's start/end-weight computation (WeightKg is
-- ciphertext, so it can't be aggregated here) - ordered ascending so the
-- caller can take First()/Last().
CREATE OR REPLACE FUNCTION dbo.usp_bodyweight_getinrange(
    p_userid uuid,
    p_fromdateutc date,
    p_todateutc date
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT bodyweightlogid, weightkg, loggedatutc
    FROM dbo.bodyweightlogs
    WHERE userid = p_userid AND loggedatutc::date BETWEEN p_fromdateutc AND p_todateutc
    ORDER BY loggedatutc ASC;
    RETURN NEXT c1;
END $$;
