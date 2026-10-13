USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

----------------------------------------------------------------------------
-- Pro / Advanced feature lists: complete and duplicate-free
----------------------------------------------------------------------------
-- Pro now gates the full Progress screen (per-exercise charts), the ranked
-- suggested-split library and the "Last time" set history, none of which the
-- plans screen advertised. This script is re-runnable: it cleans up any
-- duplicate rows, rewrites the one row that promised an unshipped feature,
-- adds the missing rows and pins the display order.

-- 1. Collapse exact duplicates (same plan, same text), keeping the oldest row.
;WITH Ranked AS (
    SELECT ROW_NUMBER() OVER (
               PARTITION BY PlanId, LTRIM(RTRIM(FeatureText))
               ORDER BY SortOrder, PlanFeatureId) AS RowNo
    FROM dbo.PlanFeatures
)
DELETE FROM Ranked WHERE RowNo > 1;
GO

-- 2. "PR prediction" was never built; the per-exercise progress charts are
--    what Pro actually ships in its place.
UPDATE pf
SET pf.FeatureText = N'Per-exercise progress charts: estimated 1RM, top set & volume',
    pf.IsHighlighted = 1
FROM dbo.PlanFeatures pf
INNER JOIN dbo.SubscriptionPlans p ON p.PlanId = pf.PlanId
WHERE p.Code = N'PRO'
  AND pf.FeatureText = N'Advanced 1RM progression & PR prediction'
  AND NOT EXISTS (
      SELECT 1 FROM dbo.PlanFeatures x
      WHERE x.PlanId = pf.PlanId
        AND x.FeatureText = N'Per-exercise progress charts: estimated 1RM, top set & volume'
  );

DELETE pf
FROM dbo.PlanFeatures pf
INNER JOIN dbo.SubscriptionPlans p ON p.PlanId = pf.PlanId
WHERE p.Code = N'PRO'
  AND pf.FeatureText = N'Advanced 1RM progression & PR prediction';
GO

-- 3. The full list per paid tier. Advanced opens with "Everything included in
--    Pro tier" and lists only what it adds, so no perk shows up twice when the
--    two plans sit side by side.
DECLARE @Features TABLE (Code NVARCHAR(30), FeatureText NVARCHAR(300), SortOrder TINYINT, IsHighlighted BIT);

INSERT INTO @Features (Code, FeatureText, SortOrder, IsHighlighted)
VALUES
    (N'PRO', N'Everything included in Free tier', 1, 0),
    (N'PRO', N'AI Monthly Overview & Volume Synthesis', 2, 1),
    (N'PRO', N'Per-exercise progress charts: estimated 1RM, top set & volume', 3, 1),
    (N'PRO', N'Full Progress screen with personal records & 1M-6M timeframes', 4, 0),
    (N'PRO', N'Suggested splits ranked for your goal, level & schedule', 5, 0),
    (N'PRO', N'"Last time" weights & reps on every exercise while you train', 6, 0),
    (N'PRO', N'Intelligent recovery & deload detection', 7, 0),
    (N'PRO', N'Custom split builder with infinite routines', 8, 0),
    (N'ADVANCED', N'Everything included in Pro tier', 1, 0),
    (N'ADVANCED', N'Weekly AI Overview with meal & split suggestions', 2, 1),
    (N'ADVANCED', N'Adaptive meal planner calibrated to load', 3, 1),
    (N'ADVANCED', N'AI-generated workout splits & diet plans on request', 4, 0),
    (N'ADVANCED', N'Unlimited saved splits & diet plans', 5, 0);

INSERT INTO dbo.PlanFeatures (PlanId, FeatureText, SortOrder, IsHighlighted)
SELECT p.PlanId, f.FeatureText, f.SortOrder, f.IsHighlighted
FROM @Features f
INNER JOIN dbo.SubscriptionPlans p ON p.Code = f.Code
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.PlanFeatures pf WHERE pf.PlanId = p.PlanId AND pf.FeatureText = f.FeatureText
);

UPDATE pf
SET pf.SortOrder = f.SortOrder,
    pf.IsHighlighted = f.IsHighlighted
FROM dbo.PlanFeatures pf
INNER JOIN dbo.SubscriptionPlans p ON p.PlanId = pf.PlanId
INNER JOIN @Features f ON f.Code = p.Code AND f.FeatureText = pf.FeatureText;
GO

-- 4. A higher tier never repeats a row its "Everything included in ..." line
--    already covers (Advanced vs Pro, Pro vs Free).
DELETE hi
FROM dbo.PlanFeatures hi
INNER JOIN dbo.SubscriptionPlans hp ON hp.PlanId = hi.PlanId
INNER JOIN dbo.SubscriptionPlans lp ON lp.Code = CASE hp.Code WHEN N'ADVANCED' THEN N'PRO' WHEN N'PRO' THEN N'FREE' END
INNER JOIN dbo.PlanFeatures lo ON lo.PlanId = lp.PlanId AND lo.FeatureText = hi.FeatureText;
GO

-- 5. Keep it that way: the admin console gets a friendly refusal from
--    usp_Admin_PlanFeature_Upsert, and this index backs it up.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UX_PlanFeatures_PlanId_FeatureText' AND object_id = OBJECT_ID(N'dbo.PlanFeatures')
)
BEGIN
    CREATE UNIQUE INDEX UX_PlanFeatures_PlanId_FeatureText ON dbo.PlanFeatures(PlanId, FeatureText);
END
GO
