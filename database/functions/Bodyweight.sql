-- WeightKg is AES-256-GCM ciphertext (Silen.Common.Helpers.FieldCipher),
-- encrypted/decrypted at the BodyweightProvider layer.

-- Returns the two most recent entries so the caller can compute the delta
-- without a second round-trip.
CREATE OR REPLACE FUNCTION dbo.usp_bodyweight_log(
    p_userid uuid,
    p_weightkg bytea
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    INSERT INTO dbo.bodyweightlogs (userid, weightkg)
    VALUES (p_userid, p_weightkg);

    -- BodyweightLogs is the chronological source of truth. Keep the profile's
    -- denormalized weight aligned with the value the user just entered so BMI,
    -- recommendations and automatically derived nutrition targets do not keep
    -- using the older onboarding weight.
    UPDATE dbo.userprofiles
    SET weightkg = p_weightkg,
        updatedatutc = dbo.sysutcdatetime()
    WHERE userid = p_userid;

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
