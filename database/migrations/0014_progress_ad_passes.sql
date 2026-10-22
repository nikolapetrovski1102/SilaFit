-- Short Progress passes a Free account earns by watching a rewarded video ad.
-- While one is unexpired the per-exercise Progress endpoints answer as they do
-- for Pro; the AI reviews never look at this table. The app re-locks the screen
-- as soon as the user leaves it, so ExpiresAtUtc is only the server's ceiling.
-- Rows are kept (not deleted on expiry) so the daily cap can count them.
CREATE TABLE dbo.progressadpasses (
    passid uuid DEFAULT gen_random_uuid() NOT NULL,
    userid uuid NOT NULL,
    grantedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    expiresatutc timestamp(3) NOT NULL,
    CONSTRAINT pk_progressadpasses PRIMARY KEY (passid),
    CONSTRAINT fk_progressadpasses_users FOREIGN KEY (userid) REFERENCES dbo.users (userid) ON DELETE CASCADE
);

CREATE INDEX ix_progressadpasses_userid_grantedatutc ON dbo.progressadpasses (userid, grantedatutc DESC);
