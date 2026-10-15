-- User-built splits only get their auto-assigned hero artwork when they're saved
-- (SplitHeroImages.Resolve in SplitService), so splits created before that shipped
-- still have a NULL heroimageurl and the app shows the stock fallback photo.
-- Backfill them with the same theme-neutral key the API would assign today.
-- Mirrors Silen.Services/Helpers/SplitHeroImages.ForSplit: the curated category
-- wins, a "Custom" split falls back to keywords in its name/description, then to
-- the generic custom artwork. (\y is PostgreSQL's word boundary, ~* ignores case.)

UPDATE dbo.workoutsplits
SET heroimageurl = 'asset:splits/' || CASE
        WHEN category IN ('PushPullLegs', 'ArnoldSplit') THEN 'push_pull_legs'
        WHEN category IN ('UpperLower', 'PHUL') THEN 'upper_lower'
        WHEN category = 'BroSplit' THEN 'bro_split'
        WHEN category = 'Powerlifting' THEN 'strength'
        WHEN category IN ('PHAT', 'GluteFocus') THEN 'hypertrophy'
        WHEN category IN ('Circuit', 'Calisthenics') THEN 'conditioning'
        WHEN category = 'FullBody' THEN 'general'
        WHEN txt ~* '\y(ppl|push[\s/&,+-]*pull|arnold)\y' THEN 'push_pull_legs'
        WHEN txt ~* '\y(upper[\s/&,+-]*lower|phul)\y' THEN 'upper_lower'
        WHEN txt ~* '\y(strength|strong(er)?|power(lifting)?|5\s*x\s*5|5/3/1|deadlifts?|squats?|compound)\y' THEN 'strength'
        WHEN txt ~* '\y(hiit|conditioning|cardio|circuits?|athletic|functional|crossfit|calisthenics|endurance|shred|cut(ting)?|fat[\s-]*loss|lean)\y' THEN 'conditioning'
        WHEN txt ~* '\y(hypertrophy|bodybuilding|mass|bulk(ing)?|muscle|size|gains|aesthetics?|phat|glutes?)\y' THEN 'hypertrophy'
        WHEN txt ~* '\y(bro|body[\s-]*part|chest|arms?|biceps?|triceps?|shoulders?)\y' THEN 'bro_split'
        WHEN txt ~* '\y(full[\s-]*body|total[\s-]*body|general|fitness|beginners?|starter|basics?)\y' THEN 'general'
        ELSE 'custom'
    END
FROM (
    -- The ci collation is nondeterministic, which regexes reject; ~* handles case.
    SELECT splitid AS id, (coalesce(name, '') || ' ' || coalesce(description, '')) COLLATE "C" AS txt
    FROM dbo.workoutsplits
) AS t
WHERE dbo.workoutsplits.splitid = t.id
  AND dbo.workoutsplits.owneruserid IS NOT NULL
  AND NULLIF(btrim(dbo.workoutsplits.heroimageurl), '') IS NULL;
