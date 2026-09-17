USE SilenDb;
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Imported long-form diet guides (dbo.DietPlans / dbo.DietPlanSections).
--
-- This is a DIFFERENT entity from dbo.NutritionPlans, which is the app's
-- day-by-day meal-schedule feature served by usp_DietPlans_* in
-- MealPlanning.sql. The name collision is explained in schema/045_DietPlans.sql:
-- dbo.DietPlans predates the meal-planning feature and holds article-style
-- guides collected from the public diet-plan catalogue (clean eating, keto,
-- IIFYM, intermittent fasting, carb cycling, paleo, mediterranean, vegan,
-- gluten-free, zone) with their ordered body sections.
--
-- These guides are shipped reference reading: always visible, never
-- user-editable, so there is no visibility predicate and no write procedure.
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.usp_DietGuides_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (500) dg.DietPlanId,
           dg.Title,
           dg.Summary,
           dg.ImageUrl,
           dg.SourceUrl,
           dg.SourceAuthor,
           dg.SortOrder,
           (SELECT COUNT(*) FROM dbo.DietPlanSections s WHERE s.DietPlanId = dg.DietPlanId) AS SectionCount
    FROM dbo.DietPlans dg
    WHERE dg.IsSystemDefault = 1
    ORDER BY dg.SortOrder, dg.Title;
END
GO

-- Result set 1: guide header (with the flattened ContentText, so a client that
-- does not render sections still has the full text). Result set 2: its ordered
-- sections. Both are always emitted (empty when the id is unknown), same
-- convention as usp_DietPlans_GetDetail / usp_Splits_GetDetail.
CREATE OR ALTER PROCEDURE dbo.usp_DietGuides_GetDetail
    @DietPlanId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT dg.DietPlanId,
           dg.Title,
           dg.Summary,
           dg.ContentText,
           dg.ImageUrl,
           dg.SourceUrl,
           dg.SourceAuthor,
           dg.SortOrder
    FROM dbo.DietPlans dg
    WHERE dg.DietPlanId = @DietPlanId
      AND dg.IsSystemDefault = 1;

    SELECT s.DietPlanSectionId,
           s.SortOrder,
           s.Heading,
           s.BodyText,
           s.ListsJson,
           s.TablesJson
    FROM dbo.DietPlanSections s
    INNER JOIN dbo.DietPlans dg ON dg.DietPlanId = s.DietPlanId
    WHERE s.DietPlanId = @DietPlanId
      AND dg.IsSystemDefault = 1
    ORDER BY s.SortOrder;
END
GO
