-- AI food scans move down to Pro, and Free accounts get a small lifetime
-- trial. Two kinds share the ledger: a meal-photo scan and a nutrition-label
-- read ("read the label with AI"). Paid tiers get a daily allowance of meal
-- scans (labels are only rate limited); a Free account gets a few trial
-- scans ever, of either kind, counted from the rows marked IsTrial so scans
-- made while subscribed never eat into it.
ALTER TABLE dbo.foodscans
    ADD COLUMN kind varchar(10) DEFAULT 'meal' NOT NULL,
    ADD COLUMN istrial boolean DEFAULT false NOT NULL;

ALTER TABLE dbo.foodscans
    ADD CONSTRAINT ck_foodscans_kind CHECK (kind IN ('meal', 'label'));
