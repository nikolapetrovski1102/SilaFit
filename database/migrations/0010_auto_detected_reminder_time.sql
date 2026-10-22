-- The gym reminder now follows the user's own training rhythm (learned from
-- when they log workouts) until they pick a time themselves; from then on the
-- picked time is used verbatim. This flag is what tells the two apart.
ALTER TABLE dbo.usersettings
    ADD COLUMN notificationtimeisuserset boolean DEFAULT false NOT NULL;

-- Every account starts at the 18:00 default, so anything else was chosen by
-- the user in Settings - keep honouring it exactly.
UPDATE dbo.usersettings
SET notificationtimeisuserset = true
WHERE notificationlocaltime <> '18:00:00';
