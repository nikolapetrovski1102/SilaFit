-- The app's UI language ('en' or 'mk'), so scheduled pushes - which run with
-- no request behind them - can be written in it. Refreshed from the app's
-- Accept-Language every time it reports an interaction (cold start/resume).
ALTER TABLE dbo.usersettings
    ADD COLUMN language varchar(5) DEFAULT 'en' NOT NULL;
