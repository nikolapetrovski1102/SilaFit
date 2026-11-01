-- Trainer documents: the PDF (or converted Word file) a trainer attaches to one
-- of their splits or diet plans, and the per-client grants that let a client
-- read it in the app. See migration 0017 for the model. Permission checks
-- (content.splits.write / content.diet_plans.write to upload, *.assign to grant)
-- live in the API; ownership is enforced here in the same transaction as the
-- write, with the same trainer-owns-their-own / manage_all-owns-everything rule
-- as the splits and diet plans themselves.

-- The owner of the split/plan a document hangs off, or NULL owner + found=false
-- when the target is gone. A user-built program (owneruserid set) is never a
-- valid target: it isn't trainer content.
CREATE OR REPLACE FUNCTION dbo.ufn_trainerdocument_targetowner(
    p_kind text,
    p_targetid uuid
) RETURNS TABLE (found boolean, owneradminuserid uuid, targetname text)
LANGUAGE sql STABLE AS $$
    SELECT true, ws.owneradminuserid, ws.name::text
    FROM dbo.workoutsplits ws
    WHERE p_kind = 'Split' AND ws.splitid = p_targetid AND ws.owneruserid IS NULL
    UNION ALL
    SELECT true, np.owneradminuserid, np.name::text
    FROM dbo.nutritionplans np
    WHERE p_kind = 'DietPlan' AND np.dietplanid = p_targetid AND np.owneruserid IS NULL;
$$;

-- Documents attached to one split or diet plan, newest first, with how many
-- clients currently hold each.
CREATE OR REPLACE FUNCTION dbo.usp_admin_trainerdocuments_getfortarget(
    p_kind text,
    p_targetid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT d.documentid,
           d.kind,
           d.splitid,
           d.dietplanid,
           d.title,
           d.originalfilename,
           d.sizebytes,
           d.createdatutc,
           d.owneradminuserid,
           owner_admin.username AS ownerusername,
           (SELECT COUNT(*)::int FROM dbo.trainerdocumentgrants g
            WHERE g.documentid = d.documentid AND g.revokedatutc IS NULL) AS activegrantcount
    FROM dbo.trainerdocuments d
    LEFT JOIN dbo.adminusers owner_admin ON owner_admin.adminuserid = d.owneradminuserid
    WHERE (p_kind = 'Split' AND d.splitid = p_targetid)
       OR (p_kind = 'DietPlan' AND d.dietplanid = p_targetid)
    ORDER BY d.createdatutc DESC;
    RETURN NEXT c1;
END $$;

-- One document with its target's owner, for the API's ownership check before it
-- streams or deletes the file.
CREATE OR REPLACE FUNCTION dbo.usp_admin_trainerdocument_get(
    p_documentid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT d.documentid,
           d.kind,
           d.splitid,
           d.dietplanid,
           d.title,
           d.originalfilename,
           d.storedfilename,
           d.sizebytes,
           d.createdatutc,
           COALESCE(ws.owneradminuserid, np.owneradminuserid) AS targetowneradminuserid
    FROM dbo.trainerdocuments d
    LEFT JOIN dbo.workoutsplits ws ON ws.splitid = d.splitid
    LEFT JOIN dbo.nutritionplans np ON np.dietplanid = d.dietplanid
    WHERE d.documentid = p_documentid;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_trainerdocument_create(
    p_kind text,
    p_targetid uuid,
    p_title text,
    p_originalfilename text,
    p_storedfilename text,
    p_sizebytes bigint,
    p_actorcanmanageall boolean DEFAULT true,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_documentid uuid := gen_random_uuid();
    v_kind text := btrim(p_kind);
    v_title text := NULLIF(btrim(p_title), '');
    v_found boolean;
    v_owneradminuserid uuid;
    v_targetname text;
BEGIN
    IF v_kind IS NULL OR v_kind NOT IN ('Split', 'DietPlan') THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A document belongs to a split or a diet plan.');
        RETURN;
    END IF;

    SELECT t.found, t.owneradminuserid, t.targetname
    INTO v_found, v_owneradminuserid, v_targetname
    FROM dbo.ufn_trainerdocument_targetowner(v_kind, p_targetid) t;

    IF v_found IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_targetid,
            CASE WHEN v_kind = 'Split' THEN 'That split no longer exists.' ELSE 'That plan no longer exists.' END);
        RETURN;
    END IF;

    IF NOT p_actorcanmanageall AND v_owneradminuserid IS DISTINCT FROM p_actoradminuserid THEN
        RETURN NEXT dbo.outcome_cursor(2, p_targetid,
            'Only the trainer who owns this ' || CASE WHEN v_kind = 'Split' THEN 'split' ELSE 'plan' END
            || ' can attach documents to it.');
        RETURN;
    END IF;

    INSERT INTO dbo.trainerdocuments
        (documentid, owneradminuserid, kind, splitid, dietplanid, title, originalfilename, storedfilename, sizebytes)
    VALUES
        (v_documentid, p_actoradminuserid, v_kind,
         CASE WHEN v_kind = 'Split' THEN p_targetid END,
         CASE WHEN v_kind = 'DietPlan' THEN p_targetid END,
         COALESCE(v_title, left(p_originalfilename, 200)), left(p_originalfilename, 260), p_storedfilename, p_sizebytes);

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Create', 'TrainerDocument', v_documentid::text,
            'Attached document ''' || COALESCE(v_title, p_originalfilename) || ''' to '
            || CASE WHEN v_kind = 'Split' THEN 'split' ELSE 'diet plan' END || ' ''' || v_targetname || '''',
            p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_documentid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_trainerdocument_delete(
    p_documentid uuid,
    p_actorcanmanageall boolean DEFAULT true,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_title text;
    v_targetowner uuid;
BEGIN
    SELECT d.title, COALESCE(ws.owneradminuserid, np.owneradminuserid)
    INTO v_title, v_targetowner
    FROM dbo.trainerdocuments d
    LEFT JOIN dbo.workoutsplits ws ON ws.splitid = d.splitid
    LEFT JOIN dbo.nutritionplans np ON np.dietplanid = d.dietplanid
    WHERE d.documentid = p_documentid;

    IF v_title IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_documentid, 'That document no longer exists.');
        RETURN;
    END IF;

    IF NOT p_actorcanmanageall AND v_targetowner IS DISTINCT FROM p_actoradminuserid THEN
        RETURN NEXT dbo.outcome_cursor(2, p_documentid, 'Only the owning trainer can remove this document.');
        RETURN;
    END IF;

    -- Grants cascade with the document.
    DELETE FROM dbo.trainerdocuments WHERE documentid = p_documentid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Delete', 'TrainerDocument', p_documentid::text,
            'Removed document ''' || v_title || '''', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_documentid, NULL);
END $$;

-- Every client grant of one document, revoked ones included (greyed out in the
-- console), with the per-client link token and how often it was opened.
CREATE OR REPLACE FUNCTION dbo.usp_admin_trainerdocumentgrants_getfordocument(
    p_documentid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT g.grantid,
           g.documentid,
           g.userid,
           u.displayname,
           u.email,
           g.token,
           g.createdatutc,
           g.revokedatutc,
           g.lastopenedatutc,
           g.opencount,
           assigned_by.username AS assignedbyusername
    FROM dbo.trainerdocumentgrants g
    INNER JOIN dbo.users u ON u.userid = g.userid
    LEFT JOIN dbo.adminusers assigned_by ON assigned_by.adminuserid = g.assignedbyadminuserid
    WHERE g.documentid = p_documentid
    ORDER BY g.revokedatutc NULLS FIRST, u.displayname NULLS FIRST, u.email NULLS FIRST;
    RETURN NEXT c1;
END $$;

-- Hands a document to one client. Idempotent while the grant is live (the
-- client keeps their link); a revoked grant comes back with p_token as a fresh
-- link so the old one stays dead.
CREATE OR REPLACE FUNCTION dbo.usp_admin_trainerdocumentgrant_assign(
    p_documentid uuid,
    p_userid uuid,
    p_token text,
    p_actorcanmanageall boolean DEFAULT true,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_title text;
    v_targetowner uuid;
    v_clientlabel text;
    v_grantid uuid;
BEGIN
    SELECT d.title, COALESCE(ws.owneradminuserid, np.owneradminuserid)
    INTO v_title, v_targetowner
    FROM dbo.trainerdocuments d
    LEFT JOIN dbo.workoutsplits ws ON ws.splitid = d.splitid
    LEFT JOIN dbo.nutritionplans np ON np.dietplanid = d.dietplanid
    WHERE d.documentid = p_documentid;

    IF v_title IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_documentid, 'That document no longer exists.');
        RETURN;
    END IF;

    IF NOT p_actorcanmanageall AND v_targetowner IS DISTINCT FROM p_actoradminuserid THEN
        RETURN NEXT dbo.outcome_cursor(2, p_documentid, 'Only the owning trainer can hand out this document.');
        RETURN;
    END IF;

    SELECT COALESCE(NULLIF(displayname, ''), NULLIF(email, ''), userid::text) INTO v_clientlabel
    FROM dbo.users
    WHERE userid = p_userid;

    IF v_clientlabel IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_userid, 'That user no longer exists.');
        RETURN;
    END IF;

    INSERT INTO dbo.trainerdocumentgrants (documentid, userid, token, assignedbyadminuserid)
    VALUES (p_documentid, p_userid, p_token, p_actoradminuserid)
    ON CONFLICT (documentid, userid) DO UPDATE
    SET token = CASE WHEN dbo.trainerdocumentgrants.revokedatutc IS NULL
                     THEN dbo.trainerdocumentgrants.token ELSE EXCLUDED.token END,
        revokedatutc = NULL,
        tickethash = CASE WHEN dbo.trainerdocumentgrants.revokedatutc IS NULL
                          THEN dbo.trainerdocumentgrants.tickethash END,
        ticketexpiresatutc = CASE WHEN dbo.trainerdocumentgrants.revokedatutc IS NULL
                                  THEN dbo.trainerdocumentgrants.ticketexpiresatutc END,
        emaillinkhash = CASE WHEN dbo.trainerdocumentgrants.revokedatutc IS NULL
                             THEN dbo.trainerdocumentgrants.emaillinkhash END,
        emaillinkexpiresatutc = CASE WHEN dbo.trainerdocumentgrants.revokedatutc IS NULL
                                     THEN dbo.trainerdocumentgrants.emaillinkexpiresatutc END,
        assignedbyadminuserid = EXCLUDED.assignedbyadminuserid
    RETURNING grantid INTO v_grantid;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Assign', 'TrainerDocumentGrant', v_grantid::text,
            'Gave document ''' || v_title || ''' to ' || v_clientlabel, p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_grantid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_trainerdocumentgrant_revoke(
    p_grantid uuid,
    p_actorcanmanageall boolean DEFAULT true,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_title text;
    v_targetowner uuid;
    v_clientlabel text;
BEGIN
    SELECT d.title, COALESCE(ws.owneradminuserid, np.owneradminuserid),
           COALESCE(NULLIF(u.displayname, ''), NULLIF(u.email, ''), u.userid::text)
    INTO v_title, v_targetowner, v_clientlabel
    FROM dbo.trainerdocumentgrants g
    INNER JOIN dbo.trainerdocuments d ON d.documentid = g.documentid
    INNER JOIN dbo.users u ON u.userid = g.userid
    LEFT JOIN dbo.workoutsplits ws ON ws.splitid = d.splitid
    LEFT JOIN dbo.nutritionplans np ON np.dietplanid = d.dietplanid
    WHERE g.grantid = p_grantid;

    IF v_title IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_grantid, 'That client no longer holds this document.');
        RETURN;
    END IF;

    IF NOT p_actorcanmanageall AND v_targetowner IS DISTINCT FROM p_actoradminuserid THEN
        RETURN NEXT dbo.outcome_cursor(2, p_grantid, 'Only the owning trainer can take this document back.');
        RETURN;
    END IF;

    UPDATE dbo.trainerdocumentgrants
    SET revokedatutc = dbo.sysutcdatetime(),
        tickethash = NULL,
        ticketexpiresatutc = NULL,
        emaillinkhash = NULL,
        emaillinkexpiresatutc = NULL
    WHERE grantid = p_grantid AND revokedatutc IS NULL;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Unassign', 'TrainerDocumentGrant', p_grantid::text,
            'Took document ''' || v_title || ''' back from ' || v_clientlabel, p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_grantid, NULL);
END $$;

-- =============================================================================
-- Viewer side. A per-client link (/api/documents/view/{token}) resolves here;
-- the API then lets it through only for an admin session that may manage the
-- document, or for the app's short-lived ticket matching tickethash.
-- =============================================================================

CREATE OR REPLACE FUNCTION dbo.usp_trainerdocument_getbytoken(
    p_token text
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT g.grantid,
           g.documentid,
           g.userid,
           u.displayname,
           u.email,
           g.revokedatutc,
           g.tickethash,
           g.ticketexpiresatutc,
           g.emaillinkhash,
           g.emaillinkexpiresatutc,
           d.title,
           d.storedfilename,
           d.kind,
           COALESCE(ws.owneradminuserid, np.owneradminuserid) AS targetowneradminuserid,
           trainer.username AS trainerusername
    FROM dbo.trainerdocumentgrants g
    INNER JOIN dbo.trainerdocuments d ON d.documentid = g.documentid
    INNER JOIN dbo.users u ON u.userid = g.userid
    LEFT JOIN dbo.workoutsplits ws ON ws.splitid = d.splitid
    LEFT JOIN dbo.nutritionplans np ON np.dietplanid = d.dietplanid
    LEFT JOIN dbo.adminusers trainer ON trainer.adminuserid = d.owneradminuserid
    WHERE g.token = p_token;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_trainerdocumentgrant_recordopen(
    p_grantid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.trainerdocumentgrants
    SET opencount = opencount + 1,
        lastopenedatutc = dbo.sysutcdatetime()
    WHERE grantid = p_grantid;
END $$;

-- The documents the calling app user holds for one split or diet plan. Drives
-- the document icon on the split / plan detail screens.
CREATE OR REPLACE FUNCTION dbo.usp_trainerdocuments_getforuser(
    p_userid uuid,
    p_kind text,
    p_targetid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT g.grantid,
           d.documentid,
           d.title,
           d.kind,
           g.createdatutc AS grantedatutc,
           trainer.username AS trainerusername
    FROM dbo.trainerdocumentgrants g
    INNER JOIN dbo.trainerdocuments d ON d.documentid = g.documentid
    LEFT JOIN dbo.adminusers trainer ON trainer.adminuserid = d.owneradminuserid
    WHERE g.userid = p_userid
      AND g.revokedatutc IS NULL
      AND d.kind = p_kind
      AND ((p_kind = 'Split' AND d.splitid = p_targetid)
           OR (p_kind = 'DietPlan' AND d.dietplanid = p_targetid))
    ORDER BY d.createdatutc DESC;
    RETURN NEXT c1;
END $$;

-- Stores the hash of a fresh viewing ticket for the caller's own live grant and
-- returns the grant's link token; returns nothing when the grant isn't theirs or
-- was taken back, which the API reports as not found.
CREATE OR REPLACE FUNCTION dbo.usp_trainerdocumentgrant_issueticket(
    p_userid uuid,
    p_grantid uuid,
    p_tickethash bytea,
    p_ticketexpiresatutc timestamp
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_token text;
BEGIN
    UPDATE dbo.trainerdocumentgrants
    SET tickethash = p_tickethash,
        ticketexpiresatutc = p_ticketexpiresatutc
    WHERE grantid = p_grantid
      AND userid = p_userid
      AND revokedatutc IS NULL
    RETURNING token INTO v_token;

    OPEN c1 FOR
    SELECT v_token AS token
    WHERE v_token IS NOT NULL;
    RETURN NEXT c1;
END $$;

-- Stores the hash of the link that goes out in the client's email and returns
-- the grant's link token; nothing when the grant was taken back. Replaces any
-- earlier email link, so only the newest email opens.
CREATE OR REPLACE FUNCTION dbo.usp_trainerdocumentgrant_issueemaillink(
    p_grantid uuid,
    p_linkhash bytea,
    p_linkexpiresatutc timestamp
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_token text;
BEGIN
    UPDATE dbo.trainerdocumentgrants
    SET emaillinkhash = p_linkhash,
        emaillinkexpiresatutc = p_linkexpiresatutc
    WHERE grantid = p_grantid
      AND revokedatutc IS NULL
    RETURNING token INTO v_token;

    OPEN c1 FOR
    SELECT v_token AS token
    WHERE v_token IS NOT NULL;
    RETURN NEXT c1;
END $$;

-- Everything the assignment notifier needs about one client and one program:
-- where to send it, whether they allow pushes, and what to call the program and
-- its trainer. Returns nothing when the user or program no longer exists.
CREATE OR REPLACE FUNCTION dbo.usp_trainerassignment_getnotifycontext(
    p_userid uuid,
    p_kind text,
    p_targetid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT u.userid,
           u.displayname,
           u.email,
           COALESCE(us.notificationsenabled, true) AS notificationsenabled,
           program.name AS programname,
           trainer.username AS trainerusername
    FROM dbo.users u
    LEFT JOIN dbo.usersettings us ON us.userid = u.userid
    INNER JOIN (
        SELECT ws.name, ws.owneradminuserid
        FROM dbo.workoutsplits ws
        WHERE p_kind = 'Split' AND ws.splitid = p_targetid
        UNION ALL
        SELECT np.name, np.owneradminuserid
        FROM dbo.nutritionplans np
        WHERE p_kind = 'DietPlan' AND np.dietplanid = p_targetid
    ) program ON true
    LEFT JOIN dbo.adminusers trainer ON trainer.adminuserid = program.owneradminuserid
    WHERE u.userid = p_userid
      AND u.isactive;
    RETURN NEXT c1;
END $$;
