-- Device (guest) login: creates the account on first call, otherwise just
-- touches LastLoginAtUtc and returns the existing row.
CREATE OR REPLACE FUNCTION dbo.usp_auth_getorcreatedeviceuser(
    p_deviceid varchar(200)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_userid uuid;
BEGIN
    -- Two first launches racing for the same device would otherwise both see no
    -- row and the second insert would fail on the DeviceId unique index.
    PERFORM pg_advisory_xact_lock(hashtextextended('device-user:' || lower(p_deviceid), 0));

    SELECT userid INTO v_userid FROM dbo.users WHERE deviceid = p_deviceid;

    IF v_userid IS NULL THEN
        v_userid := gen_random_uuid();

        INSERT INTO dbo.users (userid, deviceid, accounttier)
        VALUES (v_userid, p_deviceid, 'Guest');

        INSERT INTO dbo.userauthidentities (userid, provider, externalid)
        VALUES (v_userid, 'Device', p_deviceid);

        INSERT INTO dbo.usersettings (userid)
        VALUES (v_userid);
    END IF;

    UPDATE dbo.users SET lastloginatutc = dbo.sysutcdatetime() WHERE userid = v_userid;

    OPEN c1 FOR
    SELECT userid, deviceid, displayname, email, accounttier, createdatutc, lastloginatutc, isactive
    FROM dbo.users
    WHERE userid = v_userid;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_auth_getuserbyemail(
    p_email varchar(256)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT userid, deviceid, displayname, email, passwordhash, passwordsalt, accounttier, createdatutc, lastloginatutc, isactive
    FROM dbo.users
    WHERE email = p_email;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_auth_getuserbyid(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT userid, deviceid, displayname, email, accounttier, createdatutc, lastloginatutc, isactive
    FROM dbo.users
    WHERE userid = p_userid;
    RETURN NEXT c1;
END $$;

-- True for an account nobody can sign in to yet: no password and no sign-in
-- identity of any kind. Only usp_PartnerLead_Provision creates these - every app
-- sign-in path writes an identity - so email registration may claim one once the
-- emailed code proves the caller owns the address.
CREATE OR REPLACE FUNCTION dbo.usp_auth_isunclaimedaccount(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT EXISTS (
        SELECT 1 FROM dbo.users u
        WHERE u.userid = p_userid
          AND u.passwordhash IS NULL
          AND NOT EXISTS (SELECT 1 FROM dbo.userauthidentities ai WHERE ai.userid = u.userid)
    ) AS isunclaimed;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_auth_getidentity(
    p_provider varchar(20),
    p_externalid varchar(256)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT u.userid, u.deviceid, u.displayname, u.email, u.accounttier, u.createdatutc, u.lastloginatutc, u.isactive
    FROM dbo.userauthidentities ai
    INNER JOIN dbo.users u ON u.userid = ai.userid
    WHERE ai.provider = p_provider AND ai.externalid = p_externalid;
    RETURN NEXT c1;
END $$;

-- Registers a brand-new email/password account when p_userid is NULL, or
-- upgrades an existing Guest (device) account to Registered when p_userid is
-- supplied, preserving that user's history (streaks, sessions, logs).
CREATE OR REPLACE FUNCTION dbo.usp_auth_registeremailuser(
    p_userid uuid DEFAULT NULL,
    p_email varchar(256) DEFAULT NULL,
    p_passwordhash bytea DEFAULT NULL,
    p_passwordsalt bytea DEFAULT NULL,
    p_displayname varchar(100) DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_userid uuid := p_userid;
BEGIN
    IF v_userid IS NOT NULL THEN
        UPDATE dbo.users
        SET email = p_email,
            passwordhash = p_passwordhash,
            passwordsalt = p_passwordsalt,
            displayname = COALESCE(displayname, p_displayname),
            accounttier = 'Registered'
        WHERE userid = v_userid;
    ELSE
        v_userid := gen_random_uuid();

        INSERT INTO dbo.users (userid, email, passwordhash, passwordsalt, displayname, accounttier)
        VALUES (v_userid, p_email, p_passwordhash, p_passwordsalt, p_displayname, 'Registered');

        INSERT INTO dbo.usersettings (userid)
        VALUES (v_userid);
    END IF;

    INSERT INTO dbo.userauthidentities (userid, provider, externalid)
    VALUES (v_userid, 'Email', p_email);

    OPEN c1 FOR SELECT v_userid AS userid;
    RETURN NEXT c1;
END $$;

-- Signs in (or creates, or links to p_userid when a Guest is upgrading) via an
-- externally-verified Google/Apple identity. Token verification itself
-- happens in the API before this function is ever called.
CREATE OR REPLACE FUNCTION dbo.usp_auth_linkexternalidentity(
    p_userid uuid DEFAULT NULL,
    p_provider varchar(20) DEFAULT NULL,
    p_externalid varchar(256) DEFAULT NULL,
    p_email varchar(256) DEFAULT NULL,
    p_displayname varchar(100) DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_userid uuid := p_userid;
BEGIN
    -- A fresh sign-in (no p_userid from the client) can still belong to an
    -- account that already exists under this email - e.g. registered with a
    -- password, or linked to the other provider. Link to it instead of
    -- inserting a second Users row and hitting UX_Users_Email.
    IF v_userid IS NULL AND p_email IS NOT NULL THEN
        SELECT userid INTO v_userid FROM dbo.users WHERE email = p_email;
    END IF;

    IF v_userid IS NULL THEN
        v_userid := gen_random_uuid();

        INSERT INTO dbo.users (userid, email, displayname, accounttier)
        VALUES (v_userid, p_email, p_displayname, 'Registered');

        INSERT INTO dbo.usersettings (userid)
        VALUES (v_userid);
    ELSE
        UPDATE dbo.users
        SET email = COALESCE(email, p_email),
            displayname = COALESCE(displayname, p_displayname),
            accounttier = 'Registered'
        WHERE userid = v_userid;
    END IF;

    INSERT INTO dbo.userauthidentities (userid, provider, externalid)
    VALUES (v_userid, p_provider, p_externalid);

    OPEN c1 FOR SELECT v_userid AS userid;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_auth_updatelastlogin(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.users SET lastloginatutc = dbo.sysutcdatetime() WHERE userid = p_userid;
END $$;

-- Starts (or restarts) email/password registration: stashes everything
-- usp_Auth_RegisterEmailUser will eventually need alongside the emailed
-- code's hash, without touching dbo.users yet. Restarting for the same email
-- (a resubmitted step, or the user going back and changing their password)
-- discards whatever pending attempt existed before.
CREATE OR REPLACE FUNCTION dbo.usp_auth_upsertpendingemailverification(
    p_pendingid uuid,
    p_existinguserid uuid DEFAULT NULL,
    p_email varchar(256) DEFAULT NULL,
    p_passwordhash bytea DEFAULT NULL,
    p_passwordsalt bytea DEFAULT NULL,
    p_displayname varchar(100) DEFAULT NULL,
    p_codehash bytea DEFAULT NULL,
    p_codesalt bytea DEFAULT NULL,
    p_expiresatutc timestamp(3) DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM dbo.pendingemailverifications WHERE email = p_email;

    INSERT INTO dbo.pendingemailverifications
        (pendingid, existinguserid, email, passwordhash, passwordsalt, displayname, codehash, codesalt, expiresatutc)
    VALUES
        (p_pendingid, p_existinguserid, p_email, p_passwordhash, p_passwordsalt, p_displayname, p_codehash, p_codesalt, p_expiresatutc);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_auth_getpendingemailverification(
    p_pendingid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT pendingid, existinguserid, email, passwordhash, passwordsalt, displayname,
           codehash, codesalt, attemptcount, expiresatutc, lastsentatutc
    FROM dbo.pendingemailverifications
    WHERE pendingid = p_pendingid;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_auth_incrementpendingemailverificationattempt(
    p_pendingid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.pendingemailverifications
    SET attemptcount = attemptcount + 1
    WHERE pendingid = p_pendingid;
END $$;

-- Resend: issues a fresh code/expiry onto an already-started pending row
-- without the caller retyping email/password, and clears prior wrong
-- guesses along with it.
CREATE OR REPLACE FUNCTION dbo.usp_auth_refreshpendingemailverification(
    p_pendingid uuid,
    p_codehash bytea,
    p_codesalt bytea,
    p_expiresatutc timestamp(3)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.pendingemailverifications
    SET codehash = p_codehash,
        codesalt = p_codesalt,
        expiresatutc = p_expiresatutc,
        attemptcount = 0,
        lastsentatutc = dbo.sysutcdatetime()
    WHERE pendingid = p_pendingid;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_auth_deletependingemailverification(
    p_pendingid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM dbo.pendingemailverifications WHERE pendingid = p_pendingid;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_auth_markemailverified(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.users SET emailverifiedatutc = dbo.sysutcdatetime() WHERE userid = p_userid;
END $$;
