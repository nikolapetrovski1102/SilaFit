-- Partner shops with a discount code (migration 0017). The app lists the active
-- ones in Settings > Providers and shows the first Protein one as a small nudge
-- when a user logs a protein-heavy meal; the console manages them.

CREATE OR REPLACE FUNCTION dbo.usp_supplementproviders_getactive()
RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT providerid, name, tagline, logourl, promocode, discountlabel, shopurl, category, sortorder
    FROM dbo.supplementproviders
    WHERE isactive
    ORDER BY sortorder, name;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_supplementproviders_getall()
RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT providerid, name, tagline, logourl, promocode, discountlabel, shopurl, category,
           isactive, sortorder, createdatutc, updatedatutc
    FROM dbo.supplementproviders
    ORDER BY sortorder, name;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_supplementprovider_upsert(
    p_providerid uuid DEFAULT NULL,
    p_name text DEFAULT NULL,
    p_tagline text DEFAULT NULL,
    p_logourl text DEFAULT NULL,
    p_promocode text DEFAULT NULL,
    p_discountlabel text DEFAULT NULL,
    p_shopurl text DEFAULT NULL,
    p_category text DEFAULT 'Protein',
    p_isactive boolean DEFAULT true,
    p_sortorder integer DEFAULT 0,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_providerid uuid := p_providerid;
    v_name text := btrim(p_name);
    v_category text := COALESCE(NULLIF(btrim(p_category), ''), 'Protein');
    v_action text;
BEGIN
    IF v_name IS NULL OR v_name = '' THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'A provider name is required.');
        RETURN;
    END IF;

    -- Store the canonical spelling whatever case the console sent.
    SELECT c INTO v_category
    FROM unnest(ARRAY['Protein', 'Supplements', 'Food', 'Gear']::text[]) AS c
    WHERE c COLLATE ci = v_category;

    IF v_category IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(3, NULL, 'Category must be Protein, Supplements, Food or Gear.');
        RETURN;
    END IF;

    IF v_providerid IS NULL THEN
        v_providerid := gen_random_uuid();
        v_action := 'Create';

        INSERT INTO dbo.supplementproviders
            (providerid, name, tagline, logourl, promocode, discountlabel, shopurl, category, isactive, sortorder)
        VALUES
            (v_providerid, v_name, NULLIF(btrim(p_tagline), ''), NULLIF(btrim(p_logourl), ''),
             NULLIF(btrim(p_promocode), ''), NULLIF(btrim(p_discountlabel), ''), NULLIF(btrim(p_shopurl), ''),
             v_category, p_isactive, p_sortorder);
    ELSE
        v_action := 'Update';

        UPDATE dbo.supplementproviders
        SET name = v_name,
            tagline = NULLIF(btrim(p_tagline), ''),
            logourl = NULLIF(btrim(p_logourl), ''),
            promocode = NULLIF(btrim(p_promocode), ''),
            discountlabel = NULLIF(btrim(p_discountlabel), ''),
            shopurl = NULLIF(btrim(p_shopurl), ''),
            category = v_category,
            isactive = p_isactive,
            sortorder = p_sortorder,
            updatedatutc = dbo.sysutcdatetime()
        WHERE providerid = v_providerid;

        IF NOT FOUND THEN
            RETURN NEXT dbo.outcome_cursor(1, v_providerid, 'That provider no longer exists.');
            RETURN;
        END IF;
    END IF;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, v_action, 'SupplementProvider', v_providerid::text,
            v_action || ' provider ''' || v_name || ''''
            || CASE WHEN p_isactive THEN '' ELSE ' (hidden)' END, p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, v_providerid, NULL);
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_admin_supplementprovider_delete(
    p_providerid uuid,
    p_actoradminuserid uuid DEFAULT NULL,
    p_actorusername text DEFAULT NULL,
    p_actorip text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    v_name text;
BEGIN
    DELETE FROM dbo.supplementproviders WHERE providerid = p_providerid RETURNING name INTO v_name;

    IF v_name IS NULL THEN
        RETURN NEXT dbo.outcome_cursor(1, p_providerid, 'That provider no longer exists.');
        RETURN;
    END IF;

    INSERT INTO dbo.adminauditlog (adminuserid, username, action, entitytype, entityid, summary, createdfromip)
    VALUES (p_actoradminuserid, p_actorusername, 'Delete', 'SupplementProvider', p_providerid::text,
            'Deleted provider ''' || v_name || '''', p_actorip);

    RETURN NEXT dbo.outcome_cursor(0, p_providerid, NULL);
END $$;
