-- Three features land together here:
--
--   1. Multi-week programs. A split or diet plan can now run up to 26 weeks
--      (182 days, the longest paid subscription), its days numbered 1..182. The
--      rotation is unchanged: anchored to the Monday of the activation week,
--      advancing one slot per day and looping back to day 1 after the last week.
--
--   2. Trainer documents. A trainer uploads a PDF or Word file (Word is converted
--      to PDF on upload) for one of their splits or diet plans, optionally has AI
--      turn it into the program, and hands it to specific clients. Each hand-over
--      is a grant with its own random token, so every client has their own link
--      and a leaked link names whose copy it was. The file itself lives outside
--      the public uploads directory and is only ever streamed to the trainer (admin
--      session) or to the granted user through a short-lived ticket minted by the
--      app - the link alone never opens it.
--
--   3. Supplement providers. Partner shops with a discount code the app shows in
--      Settings and nudges toward when a user logs a protein-heavy meal. Managed in
--      the admin console; seeded with a placeholder for Proteini.si Macedonia that an
--      operator completes (logo, real code, shop link).

-- ---- 1. Multi-week programs ---------------------------------------------------
ALTER TABLE dbo.nutritionplans DROP CONSTRAINT ck_nutritionplans_durationdays;
ALTER TABLE dbo.nutritionplans
    ADD CONSTRAINT ck_nutritionplans_durationdays CHECK (durationdays >= 1 AND durationdays <= 182);

ALTER TABLE dbo.dietplandays DROP CONSTRAINT ck_dietplandays_dayindex;
ALTER TABLE dbo.dietplandays
    ADD CONSTRAINT ck_dietplandays_dayindex CHECK (dayindex >= 1 AND dayindex <= 182);

-- ---- 2. Trainer documents -----------------------------------------------------
CREATE TABLE dbo.trainerdocuments (
    documentid uuid DEFAULT uuidv7() NOT NULL,
    owneradminuserid uuid,
    kind varchar(20) COLLATE ci NOT NULL,
    splitid uuid,
    dietplanid uuid,
    title varchar(200) COLLATE ci NOT NULL,
    originalfilename varchar(260) COLLATE ci NOT NULL,
    -- Random name of the stored PDF inside the private document directory.
    storedfilename varchar(100) COLLATE ci NOT NULL,
    sizebytes bigint NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_trainerdocuments PRIMARY KEY (documentid),
    CONSTRAINT ck_trainerdocuments_kind CHECK (kind IN ('Split', 'DietPlan')),
    CONSTRAINT ck_trainerdocuments_target CHECK (
        (kind = 'Split' AND splitid IS NOT NULL AND dietplanid IS NULL)
        OR (kind = 'DietPlan' AND dietplanid IS NOT NULL AND splitid IS NULL)),
    CONSTRAINT fk_trainerdocuments_adminusers FOREIGN KEY (owneradminuserid)
        REFERENCES dbo.adminusers (adminuserid) ON DELETE SET NULL,
    CONSTRAINT fk_trainerdocuments_workoutsplits FOREIGN KEY (splitid)
        REFERENCES dbo.workoutsplits (splitid) ON DELETE CASCADE,
    CONSTRAINT fk_trainerdocuments_nutritionplans FOREIGN KEY (dietplanid)
        REFERENCES dbo.nutritionplans (dietplanid) ON DELETE CASCADE
);
CREATE INDEX ix_trainerdocuments_splitid ON dbo.trainerdocuments (splitid) WHERE splitid IS NOT NULL;
CREATE INDEX ix_trainerdocuments_dietplanid ON dbo.trainerdocuments (dietplanid) WHERE dietplanid IS NOT NULL;

-- One row per (document, client). Revoking keeps the row (and its open count)
-- for the audit trail; re-granting clears revokedatutc and issues a new token so
-- the old link stays dead.
CREATE TABLE dbo.trainerdocumentgrants (
    grantid uuid DEFAULT uuidv7() NOT NULL,
    documentid uuid NOT NULL,
    userid uuid NOT NULL,
    token varchar(64) COLLATE "C" NOT NULL,
    assignedbyadminuserid uuid,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    revokedatutc timestamp(3),
    -- SHA-256 of the short-lived viewing ticket the app last minted, and when it
    -- stops working. Only the hash is kept, the ticket itself goes to the app once.
    tickethash bytea,
    ticketexpiresatutc timestamp(3),
    lastopenedatutc timestamp(3),
    opencount integer DEFAULT 0 NOT NULL,
    CONSTRAINT pk_trainerdocumentgrants PRIMARY KEY (grantid),
    CONSTRAINT uq_trainerdocumentgrants_document_user UNIQUE (documentid, userid),
    CONSTRAINT uq_trainerdocumentgrants_token UNIQUE (token),
    CONSTRAINT fk_trainerdocumentgrants_documents FOREIGN KEY (documentid)
        REFERENCES dbo.trainerdocuments (documentid) ON DELETE CASCADE,
    CONSTRAINT fk_trainerdocumentgrants_users FOREIGN KEY (userid)
        REFERENCES dbo.users (userid) ON DELETE CASCADE,
    CONSTRAINT fk_trainerdocumentgrants_adminusers FOREIGN KEY (assignedbyadminuserid)
        REFERENCES dbo.adminusers (adminuserid) ON DELETE SET NULL
);
CREATE INDEX ix_trainerdocumentgrants_userid ON dbo.trainerdocumentgrants (userid);

-- Meals a trainer's document import created. They belong to that trainer's
-- plan, not to the public month-tagged catalog, so the catalog queries skip them.
ALTER TABLE dbo.mealsuggestions ADD COLUMN owneradminuserid uuid;
ALTER TABLE dbo.mealsuggestions
    ADD CONSTRAINT fk_mealsuggestions_adminusers FOREIGN KEY (owneradminuserid)
        REFERENCES dbo.adminusers (adminuserid) ON DELETE SET NULL;
CREATE INDEX ix_mealsuggestions_owneradminuserid ON dbo.mealsuggestions (owneradminuserid)
    WHERE owneradminuserid IS NOT NULL;

-- ---- 3. Supplement providers --------------------------------------------------
CREATE TABLE dbo.supplementproviders (
    providerid uuid DEFAULT uuidv7() NOT NULL,
    name varchar(120) COLLATE ci NOT NULL,
    tagline varchar(200) COLLATE ci,
    logourl varchar(500) COLLATE ci,
    promocode varchar(60) COLLATE ci,
    discountlabel varchar(60) COLLATE ci,
    shopurl varchar(500) COLLATE ci,
    category varchar(20) COLLATE ci DEFAULT 'Protein' NOT NULL,
    isactive boolean DEFAULT true NOT NULL,
    sortorder integer DEFAULT 0 NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    updatedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_supplementproviders PRIMARY KEY (providerid),
    CONSTRAINT ck_supplementproviders_category CHECK (category IN ('Protein', 'Supplements', 'Food', 'Gear'))
);

INSERT INTO dbo.supplementproviders (name, tagline, promocode, discountlabel, shopurl, category, sortorder)
SELECT 'Proteini.si Macedonia', 'Whey, isolates and supplements', 'SILAFIT', '10% off',
       'https://proteini.si/', 'Protein', 0
WHERE NOT EXISTS (SELECT 1 FROM dbo.supplementproviders);

-- Console permissions for the providers screen: editors and super-admins manage,
-- the read-only roles can look.
INSERT INTO dbo.adminrolepermissions (roleid, permission)
SELECT r.roleid, p.permission
FROM dbo.adminroles r
CROSS JOIN (VALUES ('content.providers.read'), ('content.providers.write')) AS p(permission)
WHERE r.name IN ('super-admin', 'content-editor')
ON CONFLICT DO NOTHING;

INSERT INTO dbo.adminrolepermissions (roleid, permission)
SELECT r.roleid, 'content.providers.read'
FROM dbo.adminroles r
WHERE r.name IN ('analyst', 'viewer')
ON CONFLICT DO NOTHING;
