-- Trainer assignment notifications. When a trainer assigns a split or diet plan
-- the client gets a push (new category) and an email carrying a secure link to
-- the program's PDF.
--
-- The emailed link needs its own credential: the app's viewing ticket
-- (tickethash) lives ten minutes and is overwritten on every in-app open, so it
-- can't be the one sitting in an inbox. emaillinkhash is the SHA-256 of a
-- separate random value that only appears in the client's own email. It expires
-- (TrainerDocuments:EmailLinkLifetimeHours), is replaced by the next email, and
-- is cleared when the grant is revoked, so a forwarded or stale email opens
-- nothing. The viewer watermarks every page with the client's name either way.
ALTER TABLE dbo.trainerdocumentgrants
    ADD COLUMN emaillinkhash bytea,
    ADD COLUMN emaillinkexpiresatutc timestamp(3);

ALTER TABLE dbo.usernotifications DROP CONSTRAINT ck_usernotifications_category;
ALTER TABLE dbo.usernotifications ADD CONSTRAINT ck_usernotifications_category CHECK (
    category = 'TrainerProgramAssigned' OR category = 'WeeklyAiPlanReady' OR category = 'MonthlyReviewUpsell'
    OR category = 'Comeback' OR category = 'Motivation' OR category = 'MealIdea' OR category = 'TrackCalories'
    OR category = 'TrackSets' OR category = 'GymReminder');
