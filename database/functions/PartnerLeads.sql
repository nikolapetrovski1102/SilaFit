-- Hands a partner-website lead over to SilaFit with PRO. Creates the account
-- when no SilaFit user has this email yet (Registered, no password and no sign-in
-- identity - the app attaches one on the user's first Apple/Google sign-in by
-- email, or on email registration, see usp_Auth_IsUnclaimedAccount), otherwise
-- uses the existing one. Calling it again for the same lead re-activates it.
--
-- Always returns one row whose Outcome is:
--   Ok              - lead active; ProGranted says whether the partner grant was
--                     written (false when the user already has a live plan of
--                     their own, which is left in charge)
--   Stale           - p_issuedatutc is older than a request already applied
--   EmailTaken      - the email's account already belongs to another lead
--   AccountDisabled - the email's account is deactivated
CREATE OR REPLACE FUNCTION dbo.usp_partnerlead_provision(
    p_partneruserid varchar(100),
    p_email varchar(256),
    p_displayname varchar(100) DEFAULT NULL,
    p_signupprovider varchar(10) DEFAULT NULL,
    p_issuedatutc timestamp(3) DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_lead dbo.partnerleads%ROWTYPE;
    v_leadexists boolean;
    v_userid uuid;
    v_userisactive boolean;
    v_isnewaccount boolean := false;
    v_progranted boolean := false;
    v_outcome text := 'Ok';
    v_planid uuid;
BEGIN
    -- Always lead first, then email: a retried call for the same lead, and two
    -- leads racing to create one email's account, both serialise here.
    PERFORM pg_advisory_xact_lock(hashtextextended('partner-lead:' || lower(p_partneruserid), 0));
    PERFORM pg_advisory_xact_lock(hashtextextended('partner-email:' || lower(p_email), 0));

    SELECT * INTO v_lead FROM dbo.partnerleads WHERE partneruserid = p_partneruserid;
    v_leadexists := FOUND;

    IF v_leadexists THEN
        v_userid := v_lead.userid;
        IF p_issuedatutc < v_lead.lastissuedatutc THEN
            v_outcome := 'Stale';
        END IF;
    ELSE
        SELECT userid, isactive INTO v_userid, v_userisactive FROM dbo.users WHERE email = p_email;
        IF v_userid IS NOT NULL AND NOT v_userisactive THEN
            v_outcome := 'AccountDisabled';
        ELSIF v_userid IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.partnerleads WHERE userid = v_userid) THEN
            v_outcome := 'EmailTaken';
        END IF;
    END IF;

    IF v_outcome = 'Ok' THEN
        IF v_userid IS NULL THEN
            v_userid := gen_random_uuid();
            v_isnewaccount := true;

            INSERT INTO dbo.users (userid, email, displayname, accounttier)
            VALUES (v_userid, p_email, p_displayname, 'Registered');

            INSERT INTO dbo.usersettings (userid)
            VALUES (v_userid);
        END IF;

        INSERT INTO dbo.partnerleads (partneruserid, userid, signupprovider, status, lastissuedatutc)
        VALUES (p_partneruserid, v_userid, p_signupprovider, 'Active', p_issuedatutc)
        ON CONFLICT (partneruserid) DO UPDATE SET
            signupprovider = p_signupprovider,
            lastissuedatutc = p_issuedatutc,
            activatedatutc = CASE WHEN dbo.partnerleads.status = 'Active'
                THEN dbo.partnerleads.activatedatutc ELSE dbo.sysutcdatetime() END,
            status = 'Active',
            cancelledatutc = NULL;

        -- A live plan the user has of their own (a store subscription, or one set
        -- from the admin console) stays in charge - replacing it would drop its
        -- receipt link, and store renewals would then stop reaching it.
        IF NOT EXISTS (
            SELECT 1 FROM dbo.usersubscriptions
            WHERE userid = v_userid
              AND NOT ispartnergrant
              AND status = 'Active'
              AND (expiresatutc IS NULL OR expiresatutc > dbo.sysutcdatetime())
        ) THEN
            SELECT planid INTO v_planid FROM dbo.subscriptionplans WHERE code = 'PRO_PARTNER';
            IF v_planid IS NULL THEN
                RAISE EXCEPTION 'No subscription plan with code PRO_PARTNER exists (migration 0015).';
            END IF;

            -- No expiry: the partner bills the lead, and the grant lasts until
            -- usp_PartnerLead_Cancel ends it.
            INSERT INTO dbo.usersubscriptions
                (userid, planid, billingcycle, status, startedatutc, expiresatutc, latestreceiptid, autorenewing, ispartnergrant)
            VALUES
                (v_userid, v_planid, 'Monthly', 'Active', dbo.sysutcdatetime(), NULL, NULL, false, true)
            ON CONFLICT (userid) DO UPDATE SET
                planid = v_planid,
                billingcycle = 'Monthly',
                startedatutc = CASE WHEN dbo.usersubscriptions.ispartnergrant AND dbo.usersubscriptions.status = 'Active'
                    THEN dbo.usersubscriptions.startedatutc ELSE dbo.sysutcdatetime() END,
                status = 'Active',
                expiresatutc = NULL,
                latestreceiptid = NULL,
                autorenewing = false,
                ispartnergrant = true;

            v_progranted := true;
        END IF;
    END IF;

    OPEN c1 FOR
    SELECT v_outcome AS outcome,
           v_userid AS userid,
           v_isnewaccount AS isnewaccount,
           v_progranted AS progranted;
    RETURN NEXT c1;
END $$;

-- Ends a partner lead's PRO immediately: the grant moves to Cancelled with its
-- expiry set to now. A plan the user bought themselves is never touched. Calling
-- it again for an already-cancelled lead is a harmless no-op.
--
-- Always returns one row whose Outcome is Ok, Stale (p_issuedatutc is older than
-- a request already applied) or NotFound (no such lead).
CREATE OR REPLACE FUNCTION dbo.usp_partnerlead_cancel(
    p_partneruserid varchar(100),
    p_issuedatutc timestamp(3)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_lead dbo.partnerleads%ROWTYPE;
    v_outcome text := 'Ok';
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended('partner-lead:' || lower(p_partneruserid), 0));

    SELECT * INTO v_lead FROM dbo.partnerleads WHERE partneruserid = p_partneruserid;

    IF NOT FOUND THEN
        v_outcome := 'NotFound';
    ELSIF p_issuedatutc < v_lead.lastissuedatutc THEN
        v_outcome := 'Stale';
    ELSE
        UPDATE dbo.partnerleads
        SET status = 'Cancelled',
            cancelledatutc = COALESCE(cancelledatutc, dbo.sysutcdatetime()),
            lastissuedatutc = p_issuedatutc
        WHERE partneruserid = p_partneruserid;

        UPDATE dbo.usersubscriptions
        SET status = 'Cancelled',
            expiresatutc = dbo.sysutcdatetime(),
            autorenewing = false
        WHERE userid = v_lead.userid
          AND ispartnergrant
          AND status = 'Active';
    END IF;

    OPEN c1 FOR
    SELECT v_outcome AS outcome,
           v_lead.userid AS userid,
           false AS isnewaccount,
           false AS progranted;
    RETURN NEXT c1;
END $$;
