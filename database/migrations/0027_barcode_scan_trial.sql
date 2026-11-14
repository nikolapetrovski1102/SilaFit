-- Corrects 0025/0026: the AI meal-photo scan stays Advanced-only, and what
-- moves to Pro is barcode scanning. A Free account gets a few barcode lookups
-- (never shown in the app); after that the scan button opens the plans. Those
-- trial lookups are 'barcode' rows in the FoodScans ledger. The 'label' kind
-- from 0025 is no longer written - label reads are open to every tier again -
-- but stays allowed so the rows written since then remain valid.
ALTER TABLE dbo.foodscans DROP CONSTRAINT ck_foodscans_kind;
ALTER TABLE dbo.foodscans
    ADD CONSTRAINT ck_foodscans_kind CHECK (kind IN ('meal', 'label', 'barcode'));

-- Plan cards: undo 0026's entries (closing the gap it opened on Pro) ...
DELETE FROM dbo.planfeatures pf
USING dbo.subscriptionplans sp
WHERE sp.planid = pf.planid
  AND ((sp.code = 'PRO' AND pf.featuretext = 'AI meal photo scan & nutrition label reader')
    OR (sp.code = 'FREE' AND pf.featuretext = '3 free AI food scans to try it out'));

-- ... then list barcode scanning on Pro in that same slot (sort order 3),
-- and the meal-photo scan on Advanced, after its weekly overview.
INSERT INTO dbo.planfeatures (planid, featuretext, sortorder, ishighlighted)
SELECT planid, 'Barcode scanning for packaged foods', 3, true
FROM dbo.subscriptionplans
WHERE code = 'PRO'
ON CONFLICT (planid, featuretext) DO NOTHING;

UPDATE dbo.planfeatures pf
SET sortorder = pf.sortorder + 1
FROM dbo.subscriptionplans sp
WHERE sp.planid = pf.planid
  AND sp.code = 'ADVANCED'
  AND pf.sortorder >= 3
  AND NOT EXISTS (
      SELECT 1 FROM dbo.planfeatures x
      WHERE x.planid = sp.planid
        AND x.featuretext = 'AI meal photo scan: ingredients, calories & macros from a photo');

INSERT INTO dbo.planfeatures (planid, featuretext, sortorder, ishighlighted)
SELECT planid, 'AI meal photo scan: ingredients, calories & macros from a photo', 3, true
FROM dbo.subscriptionplans
WHERE code = 'ADVANCED'
ON CONFLICT (planid, featuretext) DO NOTHING;
