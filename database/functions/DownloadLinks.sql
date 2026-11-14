-- Tagged download links (see migrations/0022_download_links.sql).

-- One open of https://sila.fitness/download. An unknown or inactive p_sourcecode
-- is stored as untagged (NULL) rather than refused, so the visitor still counts.
-- Also wipes the network hash of visits too old to ever be matched again, so it
-- is never kept longer than the attribution window needs it.
CREATE OR REPLACE FUNCTION dbo.usp_download_recordvisit(
    p_sourcecode varchar(40),
    p_visitorid uuid,
    p_platform varchar(10),
    p_devicelabel varchar(60),
    p_iphash bytea,
    p_retainhashhours integer
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_code varchar(40);
BEGIN
    SELECT code INTO v_code
    FROM dbo.downloadsources
    WHERE code = p_sourcecode AND isactive;

    INSERT INTO dbo.downloadvisits (sourcecode, visitorid, platform, devicelabel, iphash)
    VALUES (v_code, p_visitorid, p_platform, p_devicelabel,
            CASE WHEN p_platform = 'desktop' THEN NULL ELSE p_iphash END);

    UPDATE dbo.downloadvisits
    SET iphash = NULL
    WHERE iphash IS NOT NULL
      AND visitedatutc < dbo.sysutcdatetime() - make_interval(hours => p_retainhashhours);
END $$;

-- Credits a freshly created app account to the download-page visit that most
-- likely led to it: the newest unmatched phone visit from the same network
-- (p_iphash) in the p_windowhours before the account was created, preferring
-- one on the same platform. Only accounts created in the last
-- p_maxaccountageminutes qualify, so a returning user's device login never
-- claims someone else's visit. Safe to call more than once: an account that is
-- already credited is left alone. Returns the credited source code (NULL when
-- nothing matched, or the match was an untagged visit).
CREATE OR REPLACE FUNCTION dbo.usp_download_claiminstall(
    p_userid uuid,
    p_iphash bytea,
    p_platform varchar(10),
    p_windowhours integer,
    p_maxaccountageminutes integer
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_createdatutc timestamp(3);
    v_visitid bigint;
    v_sourcecode varchar(40);
BEGIN
    SELECT createdatutc INTO v_createdatutc
    FROM dbo.users
    WHERE userid = p_userid;

    IF v_createdatutc IS NULL
       OR v_createdatutc < dbo.sysutcdatetime() - make_interval(mins => p_maxaccountageminutes)
       OR EXISTS (SELECT 1 FROM dbo.downloadvisits WHERE matcheduserid = p_userid) THEN
        OPEN c1 FOR SELECT false AS matched, NULL::varchar AS sourcecode;
        RETURN NEXT c1;
        RETURN;
    END IF;

    SELECT visitid, sourcecode INTO v_visitid, v_sourcecode
    FROM dbo.downloadvisits
    WHERE iphash = p_iphash
      AND matcheduserid IS NULL
      AND platform <> 'desktop'
      AND visitedatutc >= v_createdatutc - make_interval(hours => p_windowhours)
      AND visitedatutc <= v_createdatutc + interval '5 minutes'
    ORDER BY (p_platform IS NOT NULL AND platform = p_platform) DESC, visitedatutc DESC
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF v_visitid IS NULL THEN
        OPEN c1 FOR SELECT false AS matched, NULL::varchar AS sourcecode;
        RETURN NEXT c1;
        RETURN;
    END IF;

    UPDATE dbo.downloadvisits
    SET matcheduserid = p_userid,
        matchedatutc = dbo.sysutcdatetime(),
        iphash = NULL
    WHERE visitid = v_visitid;

    OPEN c1 FOR SELECT true AS matched, v_sourcecode AS sourcecode;
    RETURN NEXT c1;
END $$;

-- The credited leads of visits since p_fromutc (NULL = all time), each followed
-- through to the account it ended up in: a Guest shell that signed in to an
-- existing account (users.signedinuserid) is judged by that account. "Purchased"
-- is any store receipt (including a free-month promo code redeemed through the
-- store); "payingnow" is a live store subscription, not a partner or manual grant.
CREATE OR REPLACE FUNCTION dbo.fn_download_leads(p_fromutc timestamp(3))
RETURNS TABLE (
    visitid bigint,
    sourcecode varchar(40),
    platform varchar(10),
    devicelabel varchar(60),
    visitedatutc timestamp(3),
    matchedatutc timestamp(3),
    userid uuid,
    displayname varchar(100),
    email varchar(256),
    accounttier varchar(20),
    purchased boolean,
    payingnow boolean,
    activeplancode varchar(30)
) LANGUAGE sql STABLE AS $$
    SELECT v.visitid,
           v.sourcecode,
           v.platform,
           v.devicelabel,
           v.visitedatutc,
           v.matchedatutc,
           a.userid,
           a.displayname,
           a.email,
           a.accounttier,
           EXISTS (SELECT 1 FROM dbo.subscriptionreceipts r WHERE r.userid = a.userid),
           COALESCE(s.status = 'Active' AND NOT s.ispartnergrant AND s.latestreceiptid IS NOT NULL
               AND (s.expiresatutc IS NULL OR s.expiresatutc > dbo.sysutcdatetime()), false),
           CASE WHEN s.status = 'Active' AND (s.expiresatutc IS NULL OR s.expiresatutc > dbo.sysutcdatetime())
                THEN p.code END
    FROM dbo.downloadvisits v
    JOIN dbo.users u ON u.userid = v.matcheduserid
    JOIN dbo.users a ON a.userid = COALESCE(u.signedinuserid, u.userid)
    LEFT JOIN dbo.usersubscriptions s ON s.userid = a.userid
    LEFT JOIN dbo.subscriptionplans p ON p.planid = s.planid
    WHERE p_fromutc IS NULL OR v.visitedatutc >= p_fromutc
$$;

-- The admin report for visits since p_fromutc (NULL = all time).
--
-- Cursor 1, one row per source (every configured source, even with no visits,
-- plus an untagged row): page opens, distinct devices, opens per platform, and
-- the funnel of credited installs -> signed up -> ever bought -> paying now.
-- Cursor 2, the credited leads themselves, newest first: where they came from
-- and how far they got.
CREATE OR REPLACE FUNCTION dbo.usp_download_report(
    p_fromutc timestamp(3),
    p_leadlimit integer
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    c2 refcursor;
BEGIN
    OPEN c1 FOR
    WITH visits AS (
        SELECT dv.sourcecode,
               COUNT(*)::int AS opens,
               COUNT(DISTINCT COALESCE(dv.visitorid::text, 'v' || dv.visitid::text))::int AS uniquedevices,
               COUNT(*) FILTER (WHERE dv.platform = 'ios')::int AS iosopens,
               COUNT(*) FILTER (WHERE dv.platform = 'android')::int AS androidopens,
               COUNT(*) FILTER (WHERE dv.platform = 'desktop')::int AS desktopopens,
               MAX(dv.visitedatutc) AS lastvisitatutc
        FROM dbo.downloadvisits dv
        WHERE p_fromutc IS NULL OR dv.visitedatutc >= p_fromutc
        GROUP BY dv.sourcecode
    ),
    leads AS (
        SELECT fl.sourcecode,
               COUNT(*)::int AS installs,
               COUNT(*) FILTER (WHERE fl.accounttier <> 'Guest')::int AS signedup,
               COUNT(*) FILTER (WHERE fl.purchased)::int AS purchased,
               COUNT(*) FILTER (WHERE fl.payingnow)::int AS payingnow
        FROM dbo.fn_download_leads(p_fromutc) fl
        GROUP BY fl.sourcecode
    ),
    sources AS (
        SELECT ds.code, ds.label::text AS label, ds.channel::text AS channel, ds.sortorder, ds.isactive
        FROM dbo.downloadsources ds
        UNION ALL
        SELECT NULL, 'Untagged (no ?src)', 'direct', 1000, true
    )
    SELECT s.code AS sourcecode,
           s.label,
           s.channel,
           s.isactive,
           COALESCE(v.opens, 0) AS opens,
           COALESCE(v.uniquedevices, 0) AS uniquedevices,
           COALESCE(v.iosopens, 0) AS iosopens,
           COALESCE(v.androidopens, 0) AS androidopens,
           COALESCE(v.desktopopens, 0) AS desktopopens,
           v.lastvisitatutc,
           COALESCE(l.installs, 0) AS installs,
           COALESCE(l.signedup, 0) AS signedup,
           COALESCE(l.purchased, 0) AS purchased,
           COALESCE(l.payingnow, 0) AS payingnow
    FROM sources s
    LEFT JOIN visits v ON v.sourcecode IS NOT DISTINCT FROM s.code
    LEFT JOIN leads l ON l.sourcecode IS NOT DISTINCT FROM s.code
    ORDER BY s.sortorder, s.label;
    RETURN NEXT c1;

    OPEN c2 FOR
    SELECT fl.sourcecode,
           COALESCE(ds.label, 'Untagged (no ?src)') AS sourcelabel,
           fl.platform,
           fl.devicelabel,
           fl.visitedatutc,
           fl.matchedatutc AS installedatutc,
           fl.userid,
           fl.displayname,
           fl.email,
           fl.accounttier,
           fl.purchased,
           fl.payingnow,
           fl.activeplancode
    FROM dbo.fn_download_leads(p_fromutc) fl
    LEFT JOIN dbo.downloadsources ds ON ds.code = fl.sourcecode
    ORDER BY fl.matchedatutc DESC
    LIMIT GREATEST(COALESCE(p_leadlimit, 500), 1);
    RETURN NEXT c2;
END $$;
