CREATE OR REPLACE FUNCTION dbo.usp_hydration_log(
    p_userid uuid,
    p_amountml smallint
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    INSERT INTO dbo.hydrationlogs (userid, amountml)
    VALUES (p_userid, p_amountml);

    OPEN c1 FOR
    SELECT COALESCE(SUM(amountml), 0)::int AS totalmltoday
    FROM dbo.hydrationlogs
    WHERE userid = p_userid
      AND loggedatutc::date = dbo.sysutcdatetime()::date;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_hydration_gettoday(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT COALESCE(SUM(amountml), 0)::int AS totalmltoday
    FROM dbo.hydrationlogs
    WHERE userid = p_userid
      AND loggedatutc::date = dbo.sysutcdatetime()::date;
    RETURN NEXT c1;
END $$;
