-- =============================================================================
-- Imported long-form diet guides (dbo.DietPlans / dbo.DietPlanSections).
--
-- This is a DIFFERENT entity from dbo.NutritionPlans, which is the app's
-- day-by-day meal-schedule feature served by usp_DietPlans_* in
-- MealPlanning.sql. dbo.DietPlans predates the meal-planning feature and holds
-- article-style guides collected from the public diet-plan catalogue (clean
-- eating, keto, IIFYM, intermittent fasting, carb cycling, paleo,
-- mediterranean, vegan, gluten-free, zone) with their ordered body sections.
--
-- These guides are shipped reference reading: always visible, never
-- user-editable, so there is no visibility predicate and no write function.
-- =============================================================================

CREATE OR REPLACE FUNCTION dbo.usp_dietguides_getall(
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT dg.dietplanid,
           dg.title,
           dg.summary,
           dg.imageurl,
           dg.sourceurl,
           dg.sourceauthor,
           dg.sortorder,
           (SELECT COUNT(*)::int FROM dbo.dietplansections s WHERE s.dietplanid = dg.dietplanid) AS sectioncount
    FROM dbo.dietplans dg
    WHERE dg.issystemdefault
    ORDER BY dg.sortorder, dg.title
    LIMIT 500;
    RETURN NEXT c1;
END $$;

-- Result set 1: guide header (with the flattened ContentText, so a client that
-- does not render sections still has the full text). Result set 2: its ordered
-- sections. Both are always emitted (empty when the id is unknown), same
-- convention as usp_DietPlans_GetDetail / usp_Splits_GetDetail.
CREATE OR REPLACE FUNCTION dbo.usp_dietguides_getdetail(
    p_dietplanid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    c2 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT dg.dietplanid,
           dg.title,
           dg.summary,
           dg.contenttext,
           dg.imageurl,
           dg.sourceurl,
           dg.sourceauthor,
           dg.sortorder
    FROM dbo.dietplans dg
    WHERE dg.dietplanid = p_dietplanid
      AND dg.issystemdefault;
    RETURN NEXT c1;

    OPEN c2 FOR
    SELECT s.dietplansectionid,
           s.sortorder,
           s.heading,
           s.bodytext,
           s.listsjson,
           s.tablesjson
    FROM dbo.dietplansections s
    INNER JOIN dbo.dietplans dg ON dg.dietplanid = s.dietplanid
    WHERE s.dietplanid = p_dietplanid
      AND dg.issystemdefault
    ORDER BY s.sortorder;
    RETURN NEXT c2;
END $$;
