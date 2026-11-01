-- The registered account a device's Guest shell signed into. Signing in to an
-- account that already exists (rather than upgrading the Guest row in place)
-- leaves the device id on the Guest row, so device login kept answering with
-- the Guest and the app's silent re-login on an expired token could never get
-- the signed-in account back - it wiped the session instead. Device login now
-- follows this pointer. Sign-out rotates the device id in the app, so the
-- pointer is never reached again once the user signs out.
ALTER TABLE dbo.users
    ADD COLUMN signedinuserid uuid,
    ADD CONSTRAINT fk_users_signedinuser FOREIGN KEY (signedinuserid)
        REFERENCES dbo.users (userid) ON DELETE SET NULL;
