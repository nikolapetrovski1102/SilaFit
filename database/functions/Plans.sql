CREATE OR REPLACE FUNCTION dbo.usp_plans_getall(
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    c2 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT planid, code, name, tagline, monthlyprice, yearlyprice, isfeatured, sortorder,
           appstoremonthlyproductid, appstoreyearlyproductid, playstoremonthlyproductid, playstoreyearlyproductid
    FROM dbo.subscriptionplans
    WHERE NOT ishidden
    ORDER BY sortorder;
    RETURN NEXT c1;

    OPEN c2 FOR
    SELECT planid, featuretext, sortorder, ishighlighted
    FROM dbo.planfeatures
    WHERE planid IN (SELECT planid FROM dbo.subscriptionplans WHERE NOT ishidden)
    ORDER BY planid, sortorder;
    RETURN NEXT c2;
END $$;

-- Placeholder purchase: records entitlement only. A real integration
-- validates the App Store / Play Store / payment-provider receipt server-side
-- before this function is ever called.
CREATE OR REPLACE FUNCTION dbo.usp_subscription_purchase(
    p_userid uuid,
    p_planid uuid,
    p_billingcycle varchar(10)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_expiresatutc timestamp(3) := CASE WHEN p_billingcycle = 'Yearly'
        THEN dbo.sysutcdatetime() + interval '1 year'
        ELSE dbo.sysutcdatetime() + interval '1 month' END;
BEGIN
    INSERT INTO dbo.usersubscriptions (userid, planid, billingcycle, status, startedatutc, expiresatutc)
    VALUES (p_userid, p_planid, p_billingcycle, 'Active', dbo.sysutcdatetime(), v_expiresatutc)
    ON CONFLICT (userid) DO UPDATE SET
        planid = p_planid, billingcycle = p_billingcycle, status = 'Active',
        startedatutc = dbo.sysutcdatetime(), expiresatutc = v_expiresatutc,
        ispartnergrant = false;

    OPEN c1 FOR
    SELECT userid, planid, billingcycle, status, startedatutc, expiresatutc
    FROM dbo.usersubscriptions
    WHERE userid = p_userid;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_subscription_getactive(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT us.userid, us.planid, us.billingcycle, us.status, us.startedatutc, us.expiresatutc, COALESCE(sp.entitlementcode, sp.code) AS code, sp.name,
           us.latestreceiptid, us.autorenewing, us.ispartnergrant
    FROM dbo.usersubscriptions us
    INNER JOIN dbo.subscriptionplans sp ON sp.planid = us.planid
    WHERE us.userid = p_userid;
    RETURN NEXT c1;
END $$;

-- Every paying subscriber currently entitled to a given plan, with the
-- contact details the monthly review batch needs to reach them. "Active"
-- means the subscription row says so AND it has not lapsed - a row whose
-- ExpiresAtUtc has passed is treated as expired even before an expiry sweep
-- rewrites Status. Inactive (deleted/disabled) users are excluded.
CREATE OR REPLACE FUNCTION dbo.usp_plans_getactivesubscribers(
    p_plancode varchar(30)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT
        u.userid,
        u.displayname,
        u.email,
        COALESCE(sp.entitlementcode, sp.code) AS plancode,
        us.expiresatutc
    FROM dbo.usersubscriptions us
    INNER JOIN dbo.subscriptionplans sp ON sp.planid = us.planid
    INNER JOIN dbo.users u ON u.userid = us.userid
    WHERE COALESCE(sp.entitlementcode, sp.code) = p_plancode
      AND us.status = 'Active'
      AND u.isactive
      AND (us.expiresatutc IS NULL OR us.expiresatutc > dbo.sysutcdatetime())
    ORDER BY u.createdatutc;
    RETURN NEXT c1;
END $$;

-- The complement of usp_Plans_GetActiveSubscribers: active users with an email
-- on file who are NOT currently entitled to a paid plan. This is the audience
-- for the monthly review teaser (stats + upgrade CTA), not the full AI report.
--
-- "Paid" is the PRO/ADVANCED plan-code set the rest of the app gates on
-- (SubscriptionGate.ProPlanCodes); the FREE code is a catalogue row only, so
-- free users simply have no qualifying subscription row. Excluding by explicit
-- code list means a newly added paid tier must be added here too.
CREATE OR REPLACE FUNCTION dbo.usp_plans_getnonsubscribers(
    p_maxusers integer DEFAULT 20000
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT
        u.userid,
        u.displayname,
        u.email,
        'FREE'::text AS plancode,
        NULL::timestamp(3) AS expiresatutc
    FROM dbo.users u
    WHERE u.isactive
      AND u.email IS NOT NULL
      AND btrim(u.email) <> ''
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.usersubscriptions us
          INNER JOIN dbo.subscriptionplans sp ON sp.planid = us.planid
          WHERE us.userid = u.userid
            AND us.status = 'Active'
            AND (us.expiresatutc IS NULL OR us.expiresatutc > dbo.sysutcdatetime())
            AND COALESCE(sp.entitlementcode, sp.code) IN ('PRO', 'ADVANCED')
      )
    ORDER BY u.createdatutc
    LIMIT p_maxusers;
    RETURN NEXT c1;
END $$;

-- The caller's current plan entitlements, if any. No row means either the
-- user has no active subscription (Free tier - the service layer supplies
-- hardcoded defaults for that case) or their plan has no PlanEntitlements
-- row yet.
CREATE OR REPLACE FUNCTION dbo.usp_plans_getentitlementsforuser(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT pe.planid, pe.maxactivesplits, pe.maxactivedietplans, pe.allowaigeneration
    FROM dbo.usersubscriptions us
    INNER JOIN dbo.subscriptionplans sp ON sp.planid = us.planid
    INNER JOIN dbo.planentitlements pe ON pe.planid = sp.planid
    WHERE us.userid = p_userid
      AND us.status = 'Active'
      AND (us.expiresatutc IS NULL OR us.expiresatutc > dbo.sysutcdatetime());
    RETURN NEXT c1;
END $$;

-- Claims a Silen discount code for the caller. Always returns one row whose
-- Status is Ok, Invalid (unknown or switched off), NotStarted, Expired or
-- Exhausted; PlayOfferId is only filled in for Ok. A caller who already
-- claimed the code gets Ok again without using up another redemption.
CREATE OR REPLACE FUNCTION dbo.usp_promocode_redeem(
    p_userid uuid,
    p_code varchar(40)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_promo dbo.promocodes%ROWTYPE;
    v_status text;
BEGIN
    -- Locked so two last-slot claims can't both squeeze under MaxRedemptions.
    SELECT * INTO v_promo
    FROM dbo.promocodes
    WHERE code = btrim(p_code)
    FOR UPDATE;

    IF NOT FOUND OR NOT v_promo.isactive THEN
        v_status := 'Invalid';
    ELSIF v_promo.startsatutc IS NOT NULL AND v_promo.startsatutc > dbo.sysutcdatetime() THEN
        v_status := 'NotStarted';
    ELSIF v_promo.expiresatutc IS NOT NULL AND v_promo.expiresatutc <= dbo.sysutcdatetime() THEN
        v_status := 'Expired';
    ELSIF EXISTS (SELECT 1 FROM dbo.promocoderedemptions WHERE code = v_promo.code AND userid = p_userid) THEN
        v_status := 'Ok';
    ELSIF v_promo.maxredemptions IS NOT NULL
          AND (SELECT count(*) FROM dbo.promocoderedemptions WHERE code = v_promo.code) >= v_promo.maxredemptions THEN
        v_status := 'Exhausted';
    ELSE
        INSERT INTO dbo.promocoderedemptions (code, userid) VALUES (v_promo.code, p_userid);
        v_status := 'Ok';
    END IF;

    OPEN c1 FOR
    SELECT v_status AS status,
           v_promo.code AS code,
           CASE WHEN v_status = 'Ok' THEN v_promo.playofferid END AS playofferid,
           v_promo.expiresatutc AS expiresatutc;
    RETURN NEXT c1;
END $$;
