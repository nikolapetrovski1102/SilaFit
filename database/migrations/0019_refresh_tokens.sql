-- Long-lived app sessions. The access JWT stays short (24h) because nothing can
-- revoke it; the app trades this opaque refresh token for a new one instead of
-- re-running device login, which could not restore an account the device had
-- signed in to from elsewhere and wiped the session. Only a SHA-256 of the token
-- is stored. Expiry slides forward on every use, so an app opened at least once
-- per window stays signed in; sign-out deletes the row, and account deletion
-- cascades.
CREATE TABLE dbo.refreshtokens (
    refreshtokenid uuid DEFAULT gen_random_uuid() NOT NULL,
    userid uuid NOT NULL,
    tokenhash bytea NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    lastusedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    expiresatutc timestamp(3) NOT NULL,
    CONSTRAINT pk_refreshtokens PRIMARY KEY (refreshtokenid),
    CONSTRAINT fk_refreshtokens_users FOREIGN KEY (userid) REFERENCES dbo.users (userid) ON DELETE CASCADE
);

CREATE UNIQUE INDEX ux_refreshtokens_tokenhash ON dbo.refreshtokens (tokenhash);
CREATE INDEX ix_refreshtokens_userid_lastusedatutc ON dbo.refreshtokens (userid, lastusedatutc DESC);
