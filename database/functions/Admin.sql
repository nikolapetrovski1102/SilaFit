-- Console-operator auth for the static admin dashboard. Two functions here are
-- also called by Silen.Tools.AdminProvision (enrollment/rotation), so the
-- provisioning path goes through exactly the same SQL as the runtime path.

-- Full row including credential material - only the login path and the
-- provisioning tool ever need the hash/salt/cipher.
CREATE OR REPLACE FUNCTION dbo.usp_admin_getaccountbyusername(
    p_username varchar(100)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    -- RoleId/RoleName ride along because the login path needs to know which
    -- permission set this operator will be resolved against (see AdminRbac.sql).
    -- The EmailOtp* columns are the "send email code instead" second factor -
    -- see usp_Admin_SetEmailOtp. EmailConfirmedAtUtc gates that option on top of
    -- Email being non-null - see usp_Admin_Operator_ConfirmEmail.
    OPEN c1 FOR
    SELECT u.adminuserid, u.username, u.passwordhash, u.passwordsalt, u.totpsecretcipher,
           u.failedattemptcount, u.lockeduntilutc, u.lastloginatutc, u.passwordchangedatutc,
           u.createdatutc, u.isactive, u.roleid, r.name AS rolename,
           u.email, u.emailconfirmedatutc, u.emailotpcodehash, u.emailotpcodesalt, u.emailotpexpiresatutc, u.emailotplastsentatutc
    FROM dbo.adminusers u
    LEFT JOIN dbo.adminroles r ON r.roleid = u.roleid
    WHERE u.username = p_username;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_getaccountbyid(
    p_adminuserid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT u.adminuserid, u.username, u.passwordhash, u.passwordsalt, u.totpsecretcipher,
           u.failedattemptcount, u.lockeduntilutc, u.lastloginatutc, u.passwordchangedatutc,
           u.createdatutc, u.isactive, u.roleid, r.name AS rolename,
           u.email, u.emailconfirmedatutc, u.emailotpcodehash, u.emailotpcodesalt, u.emailotpexpiresatutc, u.emailotplastsentatutc
    FROM dbo.adminusers u
    LEFT JOIN dbo.adminroles r ON r.roleid = u.roleid
    WHERE u.adminuserid = p_adminuserid;
    RETURN NEXT c1;
END $$;

-- Creates the account, or replaces its credentials when the username already
-- exists (that is what rotating means here). Either way it clears the lockout
-- counters and drops every existing session, so a rotation immediately logs any
-- other browser out instead of leaving it holding a pre-rotation session.
--
-- p_email: NULL means "leave whatever email is already on file alone" - the
-- tool's --keep-totp-style default for a plain credential rotation. Pass an
-- empty string to explicitly clear it.
CREATE OR REPLACE FUNCTION dbo.usp_admin_upsertaccount(
    p_username varchar(100),
    p_passwordhash bytea,
    p_passwordsalt bytea,
    p_totpsecretcipher bytea,
    p_email varchar(256) DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_adminuserid uuid;
BEGIN
    SELECT adminuserid INTO v_adminuserid FROM dbo.adminusers WHERE username = p_username FOR UPDATE;

    IF v_adminuserid IS NULL THEN
        v_adminuserid := gen_random_uuid();

        INSERT INTO dbo.adminusers (adminuserid, username, passwordhash, passwordsalt, totpsecretcipher, email)
        VALUES (v_adminuserid, p_username, p_passwordhash, p_passwordsalt, p_totpsecretcipher, NULLIF(p_email, ''));
    ELSE
        UPDATE dbo.adminusers
        SET passwordhash = p_passwordhash,
            passwordsalt = p_passwordsalt,
            totpsecretcipher = p_totpsecretcipher,
            failedattemptcount = 0,
            lockeduntilutc = NULL,
            passwordchangedatutc = dbo.sysutcdatetime(),
            isactive = true,
            email = CASE WHEN p_email IS NULL THEN email ELSE NULLIF(p_email, '') END
        WHERE adminuserid = v_adminuserid;

        DELETE FROM dbo.adminsessions WHERE adminuserid = v_adminuserid;
    END IF;

    OPEN c1 FOR SELECT v_adminuserid AS adminuserid;
    RETURN NEXT c1;
END $$;

-- Bumps the shared failure counter for both factors and locks the account once
-- p_lockoutthreshold consecutive failures are reached. Returns the resulting
-- state so the caller can tell the user how long they're locked out for.
CREATE OR REPLACE FUNCTION dbo.usp_admin_recordfailedlogin(
    p_adminuserid uuid,
    p_lockoutthreshold integer,
    p_lockoutminutes integer
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    UPDATE dbo.adminusers
    SET failedattemptcount = failedattemptcount + 1,
        lockeduntilutc = CASE
            WHEN failedattemptcount + 1 >= p_lockoutthreshold
                THEN dbo.sysutcdatetime() + make_interval(mins => p_lockoutminutes)
            ELSE lockeduntilutc
        END
    WHERE adminuserid = p_adminuserid;

    OPEN c1 FOR
    SELECT failedattemptcount, lockeduntilutc
    FROM dbo.adminusers
    WHERE adminuserid = p_adminuserid;
    RETURN NEXT c1;
END $$;

-- Also burns the email-OTP fields whether or not this sign-in actually used
-- one, so a stale mailed code never verifies twice and a leftover row can't
-- outlive the session it belonged to.
CREATE OR REPLACE FUNCTION dbo.usp_admin_recordsuccessfullogin(
    p_adminuserid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.adminusers
    SET failedattemptcount = 0,
        lockeduntilutc = NULL,
        lastloginatutc = dbo.sysutcdatetime(),
        emailotpcodehash = NULL,
        emailotpcodesalt = NULL,
        emailotpexpiresatutc = NULL,
        emailotplastsentatutc = NULL
    WHERE adminuserid = p_adminuserid;
END $$;

-- Sets the "send email code instead" second factor onto the row for the emailed
-- code AdminAuthService just generated. p_email is re-passed and checked rather
-- than trusted from an earlier read, so this can never silently write a code
-- for an account whose email was cleared between the two calls.
CREATE OR REPLACE FUNCTION dbo.usp_admin_setemailotp(
    p_adminuserid uuid,
    p_email varchar(256),
    p_codehash bytea,
    p_codesalt bytea,
    p_expiresatutc timestamp(3)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.adminusers
    SET emailotpcodehash = p_codehash,
        emailotpcodesalt = p_codesalt,
        emailotpexpiresatutc = p_expiresatutc,
        emailotplastsentatutc = dbo.sysutcdatetime()
    WHERE adminuserid = p_adminuserid
      AND email = p_email;
END $$;

-- Standalone email set/clear for the provisioning tool's --set-email, kept
-- separate from usp_Admin_UpsertAccount so an operator's recovery address can
-- be changed without rotating their password/TOTP secret or dropping sessions.
CREATE OR REPLACE FUNCTION dbo.usp_admin_setemail(
    p_adminuserid uuid,
    p_email varchar(256) DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.adminusers
    SET email = NULLIF(p_email, '')
    WHERE adminuserid = p_adminuserid;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_createsession(
    p_adminuserid uuid,
    p_tokenhash bytea,
    p_expiresatutc timestamp(3),
    p_absoluteexpiresatutc timestamp(3),
    p_createdfromip varchar(64) DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_adminsessionid uuid := gen_random_uuid();
BEGIN
    -- Cheap housekeeping on the only path that creates rows.
    DELETE FROM dbo.adminsessions
    WHERE absoluteexpiresatutc < dbo.sysutcdatetime() OR expiresatutc < dbo.sysutcdatetime();

    INSERT INTO dbo.adminsessions (adminsessionid, adminuserid, tokenhash, expiresatutc, absoluteexpiresatutc, createdfromip)
    VALUES (v_adminsessionid, p_adminuserid, p_tokenhash, p_expiresatutc, p_absoluteexpiresatutc, p_createdfromip);

    OPEN c1 FOR SELECT v_adminsessionid AS adminsessionid;
    RETURN NEXT c1;
END $$;

-- Resolves a cookie to a session. Returns no row when the session is unknown,
-- idle-expired, past its absolute ceiling, or the account has been deactivated -
-- all four are the same thing as far as the caller is concerned.
CREATE OR REPLACE FUNCTION dbo.usp_admin_getsession(
    p_tokenhash bytea
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT s.adminsessionid, s.adminuserid, s.expiresatutc, s.absoluteexpiresatutc,
           s.lastseenatutc, u.username
    FROM dbo.adminsessions s
    INNER JOIN dbo.adminusers u ON u.adminuserid = s.adminuserid
    WHERE s.tokenhash = p_tokenhash
      AND u.isactive
      AND s.expiresatutc > dbo.sysutcdatetime()
      AND s.absoluteexpiresatutc > dbo.sysutcdatetime();
    RETURN NEXT c1;
END $$;

-- Slides the idle deadline. The absolute ceiling is enforced here rather than
-- in the caller so a stale client can't push it out by heartbeat.
CREATE OR REPLACE FUNCTION dbo.usp_admin_touchsession(
    p_adminsessionid uuid,
    p_expiresatutc timestamp(3)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.adminsessions
    SET lastseenatutc = dbo.sysutcdatetime(),
        expiresatutc = LEAST(p_expiresatutc, absoluteexpiresatutc)
    WHERE adminsessionid = p_adminsessionid;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_deletesession(
    p_tokenhash bytea
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM dbo.adminsessions WHERE tokenhash = p_tokenhash;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_deleteallsessions(
    p_adminuserid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM dbo.adminsessions WHERE adminuserid = p_adminuserid;
END $$;
