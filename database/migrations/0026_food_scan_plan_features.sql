-- AI food scanning moved down to Pro (0025): list it on the Pro card, right
-- after the highlighted AI and progress features, and tell Free what it gets
-- to try. Plan features are admin-editable, so plans are looked up by code and
-- the inserts skip a text that is already there (ux_planfeatures_planid_featuretext).

-- Make room at sort order 3 on Pro.
UPDATE dbo.planfeatures pf
SET sortorder = pf.sortorder + 1
FROM dbo.subscriptionplans sp
WHERE sp.planid = pf.planid
  AND sp.code = 'PRO'
  AND pf.sortorder >= 3
  AND NOT EXISTS (
      SELECT 1 FROM dbo.planfeatures x
      WHERE x.planid = sp.planid
        AND x.featuretext = 'AI meal photo scan & nutrition label reader');

INSERT INTO dbo.planfeatures (planid, featuretext, sortorder, ishighlighted)
SELECT planid, 'AI meal photo scan & nutrition label reader', 3, true
FROM dbo.subscriptionplans
WHERE code = 'PRO'
ON CONFLICT (planid, featuretext) DO NOTHING;

INSERT INTO dbo.planfeatures (planid, featuretext, sortorder, ishighlighted)
SELECT sp.planid, '3 free AI food scans to try it out',
       COALESCE((SELECT MAX(pf.sortorder) FROM dbo.planfeatures pf WHERE pf.planid = sp.planid), 0) + 1,
       false
FROM dbo.subscriptionplans sp
WHERE sp.code = 'FREE'
ON CONFLICT (planid, featuretext) DO NOTHING;
