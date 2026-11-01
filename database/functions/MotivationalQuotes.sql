-- Motivational lines for the app's splash screen (migration 0018). Read
-- anonymously - the splash shows them before sign-in has finished.

CREATE OR REPLACE FUNCTION dbo.usp_motivationalquotes_getactive()
RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT quoteid, text, author, sortorder
    FROM dbo.motivationalquotes
    WHERE isactive
    ORDER BY sortorder, createdatutc;
    RETURN NEXT c1;
END $$;
