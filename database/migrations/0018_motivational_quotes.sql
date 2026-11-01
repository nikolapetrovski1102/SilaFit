-- Motivational lines shown at the bottom of the app's splash screen while it
-- loads. The app caches the active set on the device, so a new or edited
-- line reaches users on their next launch with signal, and every launch
-- (including offline ones) shows whatever it saved last.

CREATE TABLE dbo.motivationalquotes (
    quoteid uuid DEFAULT uuidv7() NOT NULL,
    text varchar(200) COLLATE ci NOT NULL,
    author varchar(80) COLLATE ci,
    isactive boolean DEFAULT true NOT NULL,
    sortorder integer DEFAULT 0 NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    updatedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_motivationalquotes PRIMARY KEY (quoteid),
    CONSTRAINT ck_motivationalquotes_text CHECK (btrim(text) <> '')
);

INSERT INTO dbo.motivationalquotes (text, author, sortorder)
SELECT q.text, q.author, q.sortorder
FROM (VALUES
    ('Small steps every day add up to big results.', NULL, 0),
    ('You don''t have to be extreme, just consistent.', NULL, 1),
    ('The only bad workout is the one that didn''t happen.', NULL, 2),
    ('Discipline is choosing what you want most over what you want now.', NULL, 3),
    ('Strong is built one rep at a time.', NULL, 4),
    ('Show up today. Your future self is watching.', NULL, 5),
    ('Progress, not perfection.', NULL, 6),
    ('Fuel your body like it''s on your side - because it is.', NULL, 7),
    ('Rest is part of the plan, not a break from it.', NULL, 8),
    ('Keep the streak alive. Keep the fire burning.', NULL, 9),
    ('It never gets easier. You just get stronger.', NULL, 10),
    ('Motivation gets you started. Habit keeps you going.', NULL, 11)
) AS q(text, author, sortorder)
WHERE NOT EXISTS (SELECT 1 FROM dbo.motivationalquotes);
