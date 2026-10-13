-- Role, permission and operator administration for the console.
--
-- Every function here that changes something writes its own audit row inside the
-- same transaction, so a mutation that commits without a trail is not possible -
-- including changes made by an operator who later has their access revoked.
--
-- Mutating functions return one row: Outcome / EntityId / Detail. Outcome is the
-- contract the service layer maps to HTTP (0 = done, 1 = not found, 2 = conflict,
-- 3 = rejected input), which keeps business rules out of the functions and the
-- messages in one place. See AdminWriteOutcome in Silen.Common/Models.

-- Permissions for one operator, resolved from their role at read time. The API
-- calls this on every request, so a privilege change takes effect immediately
-- instead of when a session happens to be re-created.
CREATE OR REPLACE FUNCTION dbo.usp_admin_getpermissions(
    p_adminuserid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT rp.permission
    FROM dbo.adminusers u
    INNER JOIN dbo.adminrolepermissions rp ON rp.roleid = u.roleid
    WHERE u.adminuserid = p_adminuserid
      AND u.isactive
    ORDER BY rp.permission;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_roles_getall(
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT r.roleid,
           r.name,
           r.description,
           r.issystemrole,
           (SELECT COUNT(*)::int FROM dbo.adminrolepermissions p WHERE p.roleid = r.roleid) AS permissioncount,
           (SELECT COUNT(*)::int FROM dbo.adminusers u WHERE u.roleid = r.roleid) AS operatorcount
    FROM dbo.adminroles r
    ORDER BY r.issystemrole DESC, r.name;
    RETURN NEXT c1;
END $$;

-- One row per permission, plus a single all-NULL row for a role that exists but
-- has none - so the caller can tell "unknown role" (no rows) from "role with no
-- permissions" without a second round trip.
CREATE OR REPLACE FUNCTION dbo.usp_admin_rolepermissions_getforrole(
    p_rolename text
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT r.name AS rolename, r.issystemrole, rp.permission
    FROM dbo.adminroles r
    LEFT JOIN dbo.adminrolepermissions rp ON rp.roleid = r.roleid
    WHERE r.name = p_rolename
    ORDER BY rp.permission NULLS FIRST;
    RETURN NEXT c1;
END $$;

-- Custom (non-system) roles only. A shipped role's permission set is immutable so
-- that operators.manage can never be stripped from super-admin by accident.
CREATE OR REPLACE FUNCTION dbo.usp_admin_role_create(
    p_name text,
    p_description text DEFAULT NULL,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_name text := btrim(p_name);
    v_roleid uuid;
BEGIN
    IF v_name IS NULL OR v_name = '' THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A role name is required.');
        RETURN;
    END IF;

    IF EXISTS (SELECT 1 FROM dbo.adminroles WHERE name = v_name) THEN
        RETURN NEXT dbo.outcome_cursor(2, NULL, 'A role named ''' || v_name || ''' already exists.');
        RETURN;
    END IF;

    v_roleid := gen_random_uuid();

    INSERT INTO dbo.adminroles (roleid, name, description, issystemrole)
    VALUES (v_roleid, v_name, p_description, false);

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Create', 'AdminRole', v_roleid::text,
            'Created role ''' || v_name || ''' (starts with no permissions)', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_roleid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_role_delete(
    p_name text,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_name text := btrim(p_name);
    v_roleid uuid;
    v_issystemrole boolean;
    v_operatorcount integer;
BEGIN
    SELECT roleid, issystemrole INTO v_roleid, v_issystemrole
    FROM dbo.adminroles
    WHERE name = v_name;

    IF v_roleid IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, NULL, 'No role named ''' || v_name || '''.');
        RETURN;
    END IF;

    IF v_issystemrole THEN
        RETURN NEXT dbo.outcome_cursor(2, v_roleid, '''' || v_name || ''' is a built-in role and cannot be deleted.');
        RETURN;
    END IF;

    SELECT COUNT(*) INTO v_operatorcount FROM dbo.adminusers WHERE roleid = v_roleid;

    IF v_operatorcount > 0 THEN
        RETURN NEXT dbo.outcome_cursor(2, v_roleid,
            'Still assigned to ' || v_operatorcount::text || ' operator(s); move them to another role first.');
        RETURN;
    END IF;

    -- Permissions cascade with the role.
    DELETE FROM dbo.adminroles WHERE roleid = v_roleid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Delete', 'AdminRole', v_roleid::text,
            'Deleted role ''' || v_name || '''', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_roleid, NULL);
END $$;

-- Grants or revokes one permission on one custom role - the fine-grained control
-- behind "some operators get read-write, some get read-only".
CREATE OR REPLACE FUNCTION dbo.usp_admin_rolepermission_set(
    p_rolename text,
    p_permission text,
    p_granted boolean,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_rolename text := btrim(p_rolename);
    v_permission text := btrim(p_permission);
    v_roleid uuid;
    v_issystemrole boolean;
BEGIN
    SELECT roleid, issystemrole INTO v_roleid, v_issystemrole
    FROM dbo.adminroles
    WHERE name = v_rolename;

    IF v_roleid IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, NULL, 'No role named ''' || v_rolename || '''.');
        RETURN;
    END IF;

    IF v_issystemrole THEN
        RETURN NEXT dbo.outcome_cursor(2, v_roleid,
            '''' || v_rolename || ''' is a built-in role; create a custom role to vary its permissions.');
        RETURN;
    END IF;

    IF v_permission IS NULL OR v_permission = '' THEN
        RETURN NEXT dbo.outcome_cursor(3, v_roleid, 'A permission name is required.');
        RETURN;
    END IF;

    IF p_granted THEN
        INSERT INTO dbo.adminrolepermissions (roleid, permission)
        VALUES (v_roleid, v_permission)
        ON CONFLICT (roleid, permission) DO NOTHING;
    ELSE
        DELETE FROM dbo.adminrolepermissions WHERE roleid = v_roleid AND permission = v_permission;
    END IF;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, CASE WHEN p_granted THEN 'Grant' ELSE 'Revoke' END,
            'AdminRole', v_roleid::text,
            CASE WHEN p_granted
                 THEN 'Granted ''' || v_permission || ''' to role ''' || v_rolename || ''''
                 ELSE 'Revoked ''' || v_permission || ''' from role ''' || v_rolename || '''' END,
            p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_roleid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_operators_getall(
    p_includeinactive boolean DEFAULT false
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT u.adminuserid,
           u.username,
           u.roleid,
           r.name AS rolename,
           u.isactive,
           u.lastloginatutc,
           u.createdatutc,
           u.email,
           u.emailconfirmedatutc,
           (SELECT COUNT(*)::int FROM dbo.adminsessions s WHERE s.adminuserid = u.adminuserid) AS activesessioncount
    FROM dbo.adminusers u
    LEFT JOIN dbo.adminroles r ON r.roleid = u.roleid
    WHERE u.isactive OR p_includeinactive
    ORDER BY u.username;
    RETURN NEXT c1;
END $$;

-- One operator by username, regardless of active state, so operations that only
-- need a single account's address/confirmation state (e.g. re-sending an email
-- confirmation) do not have to list every operator. Deliberately selects the same
-- columns as usp_admin_operators_getall so AdminContentRowMapper.MapOperator reads
-- it unchanged.
CREATE OR REPLACE FUNCTION dbo.usp_admin_operator_getbyusername(
    p_username text
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT u.adminuserid,
           u.username,
           u.roleid,
           r.name AS rolename,
           u.isactive,
           u.lastloginatutc,
           u.createdatutc,
           u.email,
           u.emailconfirmedatutc,
           (SELECT COUNT(*)::int FROM dbo.adminsessions s WHERE s.adminuserid = u.adminuserid) AS activesessioncount
    FROM dbo.adminusers u
    LEFT JOIN dbo.adminroles r ON r.roleid = u.roleid
    WHERE u.username = btrim(p_username);
    RETURN NEXT c1;
END $$;

-- Creates a brand-new operator from the dashboard (operators.manage). Deliberately
-- separate from usp_admin_upsertaccount: that function is the provisioning CLI's
-- rotate-or-create tool and will happily overwrite an existing username's
-- credentials, which is exactly the wrong behavior for an HTTP endpoint an
-- authenticated operator can call - a typo'd "existing" username must never
-- silently reset someone else's password and kill their sessions. This function
-- only ever inserts, and refuses (Conflict) if the username is already taken.
-- p_email is stored unconfirmed (emailconfirmedatutc stays NULL) until the
-- operator clicks the link in their confirmation email - see
-- usp_admin_operator_confirmemail.
CREATE OR REPLACE FUNCTION dbo.usp_admin_operator_create(
    p_username text,
    p_passwordhash bytea,
    p_passwordsalt bytea,
    p_totpsecretcipher bytea,
    p_email text DEFAULT NULL,
    p_rolename text DEFAULT NULL,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_username text := btrim(p_username);
    v_rolename text := NULLIF(btrim(p_rolename), '');
    v_email text := NULLIF(btrim(p_email), '');
    v_roleid uuid;
    v_adminuserid uuid;
BEGIN
    IF v_username IS NULL OR v_username = '' THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A username is required.');
        RETURN;
    END IF;

    IF EXISTS (SELECT 1 FROM dbo.adminusers WHERE username = v_username) THEN
        RETURN NEXT dbo.outcome_cursor(2, NULL, 'An operator named ''' || v_username || ''' already exists.');
        RETURN;
    END IF;

    IF v_rolename IS NOT NULL THEN
        SELECT roleid INTO v_roleid FROM dbo.adminroles WHERE name = v_rolename;

        IF v_roleid IS NULL THEN
            RETURN NEXT dbo.outcome_cursor(1, NULL, 'No role named ''' || v_rolename || '''.');
            RETURN;
        END IF;
    END IF;

    v_adminuserid := gen_random_uuid();

    INSERT INTO dbo.adminusers (adminuserid, username, passwordhash, passwordsalt, totpsecretcipher, email, roleid)
    VALUES (v_adminuserid, v_username, p_passwordhash, p_passwordsalt, p_totpsecretcipher, v_email, v_roleid);

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Create', 'AdminOperator', v_adminuserid::text,
            'Created operator ''' || v_username || ''' with role ''' || COALESCE(v_rolename, 'none') || '''', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_adminuserid, NULL);
END $$;

-- Moving an operator between roles also drops their live sessions: privilege is
-- re-read per request so the change is immediate anyway, but a demotion should not
-- leave a console tab sitting mid-edit holding a page it can no longer save.
CREATE OR REPLACE FUNCTION dbo.usp_admin_operator_setrole(
    p_username text,
    p_rolename text,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_username text := btrim(p_username);
    v_rolename text := btrim(p_rolename);
    v_adminuserid uuid;
    v_roleid uuid;
    v_currentrolename text;
BEGIN
    SELECT u.adminuserid, r.name INTO v_adminuserid, v_currentrolename
    FROM dbo.adminusers u
    LEFT JOIN dbo.adminroles r ON r.roleid = u.roleid
    WHERE u.username = v_username;

    IF v_adminuserid IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, NULL, 'No operator named ''' || v_username || '''.');
        RETURN;
    END IF;

    SELECT roleid INTO v_roleid FROM dbo.adminroles WHERE name = v_rolename;

    IF v_roleid IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, v_adminuserid, 'No role named ''' || v_rolename || '''.');
        RETURN;
    END IF;

    UPDATE dbo.adminusers SET roleid = v_roleid WHERE adminuserid = v_adminuserid;

    DELETE FROM dbo.adminsessions WHERE adminuserid = v_adminuserid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'AssignRole', 'AdminOperator', v_adminuserid::text,
            'Moved operator ''' || v_username || ''' from role ''' || COALESCE(v_currentrolename, 'none') || ''' to ''' || v_rolename
            || ''' (sessions revoked)', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_adminuserid, NULL);
END $$;

-- Deactivating is the supported way to retire an operator: the row (and its trail)
-- stays, but every session dies immediately and sign-in stops working.
CREATE OR REPLACE FUNCTION dbo.usp_admin_operator_setactive(
    p_username text,
    p_isactive boolean,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_username text := btrim(p_username);
    v_adminuserid uuid;
BEGIN
    SELECT adminuserid INTO v_adminuserid FROM dbo.adminusers WHERE username = v_username;

    IF v_adminuserid IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, NULL, 'No operator named ''' || v_username || '''.');
        RETURN;
    END IF;

    UPDATE dbo.adminusers SET isactive = p_isactive WHERE adminuserid = v_adminuserid;

    IF NOT p_isactive THEN
        DELETE FROM dbo.adminsessions WHERE adminuserid = v_adminuserid;
    END IF;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, CASE WHEN p_isactive THEN 'Activate' ELSE 'Deactivate' END,
            'AdminOperator', v_adminuserid::text,
            CASE WHEN p_isactive
                 THEN 'Activated operator ''' || v_username || ''''
                 ELSE 'Deactivated operator ''' || v_username || ''' (sessions revoked)' END,
            p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_adminuserid, NULL);
END $$;

-- Confirms the email an operator was created with, reached by clicking the link
-- in the confirmation email (see AdminRbacService.ConfirmOperatorEmailAsync).
-- Deliberately not gated by a permission or actor lookup the way the rest of
-- this file is: the caller has no session yet, and the possession of a valid,
-- unexpired token (verified by the service before this ever runs) *is* the
-- authorization. p_email is re-checked against the row rather than trusted, so a
-- stale link from before the address was changed can never confirm the new one.
-- Confirming an already-confirmed address is treated as success, not an error -
-- clicking the link twice should never look like a failure.
CREATE OR REPLACE FUNCTION dbo.usp_admin_operator_confirmemail(
    p_adminuserid uuid,
    p_email text,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_username text;
    v_alreadyconfirmed boolean;
BEGIN
    SELECT username, emailconfirmedatutc IS NOT NULL INTO v_username, v_alreadyconfirmed
    FROM dbo.adminusers
    WHERE adminuserid = p_adminuserid AND email = p_email;

    IF v_username IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, NULL, 'This confirmation link no longer matches an operator on file.');
        RETURN;
    END IF;

    IF v_alreadyconfirmed THEN
        RETURN NEXT dbo.outcome_cursor(0, p_adminuserid, 'Email already confirmed.');
        RETURN;
    END IF;

    UPDATE dbo.adminusers SET emailconfirmedatutc = dbo.sysutcdatetime() WHERE adminuserid = p_adminuserid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_adminuserid, v_username, 'ConfirmEmail', 'AdminOperator', p_adminuserid::text,
            'Confirmed email for ''' || v_username || '''', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_adminuserid, NULL);
END $$;

-- Newest first. The cap is enforced here rather than by the caller so no request
-- can ask for the whole table.
CREATE OR REPLACE FUNCTION dbo.usp_admin_audit_getrecent(
    p_limit integer DEFAULT 50
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_limit integer := p_limit;
BEGIN
    IF v_limit IS NULL OR v_limit < 1 THEN v_limit := 50; END IF;
    IF v_limit > 200 THEN v_limit := 200; END IF;

    OPEN c1 FOR
    SELECT auditid,
           adminuserid,
           username,
           action,
           entitytype,
           entityid,
           summary,
           createdfromip,
           createdatutc
    FROM dbo.adminauditlog
    ORDER BY createdatutc DESC, auditid DESC
    LIMIT v_limit;
    RETURN NEXT c1;
END $$;
