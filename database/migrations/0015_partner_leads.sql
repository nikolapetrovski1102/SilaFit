-- Leads that signed up on the partner website (with Apple, Google or email) and
-- were handed over to SilaFit with PRO included. The partner bills them, so their
-- PRO has no expiry and lasts until the partner calls the cancel endpoint.
--
-- PartnerUserId is the partner site's own id for the lead; UserId is the SilaFit
-- account that was created (or matched by email) for it. LastIssuedAtUtc is the
-- newest payload timestamp applied to the lead, so a replayed or out-of-order
-- request (an old "provision" arriving after a "cancel") is refused.
CREATE TABLE dbo.partnerleads (
    partneruserid varchar(100) COLLATE ci NOT NULL,
    userid uuid NOT NULL,
    signupprovider varchar(10) COLLATE ci NOT NULL,
    status varchar(20) COLLATE ci DEFAULT 'Active' NOT NULL,
    lastissuedatutc timestamp(3) NOT NULL,
    activatedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    cancelledatutc timestamp(3),
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_partnerleads PRIMARY KEY (partneruserid),
    CONSTRAINT uq_partnerleads_userid UNIQUE (userid),
    CONSTRAINT fk_partnerleads_users FOREIGN KEY (userid) REFERENCES dbo.users (userid),
    CONSTRAINT ck_partnerleads_status CHECK (status IN ('Active', 'Cancelled')),
    CONSTRAINT ck_partnerleads_signupprovider CHECK (signupprovider IN ('Apple', 'Google', 'Email'))
);

-- Marks a plan granted through the partner rather than bought in a store, so
-- store notifications leave it alone and the partner's cancel only ever ends
-- its own grant. Every other write path (store activation, the admin console)
-- puts it back to false.
ALTER TABLE dbo.usersubscriptions ADD COLUMN ispartnergrant boolean DEFAULT false NOT NULL;

-- A plan can stand in for another tier: entitlementcode is the code the app and
-- every feature check see (usp_Subscription_GetActive and the paid-audience
-- queries read COALESCE(entitlementcode, code)), while code stays the plan's own
-- identity for the admin console and reporting. A hidden plan is left out of the
-- in-app catalogue - nobody can buy it, it is only ever granted.
ALTER TABLE dbo.subscriptionplans
    ADD COLUMN entitlementcode varchar(30) COLLATE ci,
    ADD COLUMN ishidden boolean DEFAULT false NOT NULL;

-- PRO for partner leads: unlocks exactly what PRO does and reads as PRO in the
-- app, but stays its own plan so partner users can be counted, priced and
-- changed apart from store subscribers. Free here - the partner bills the lead.
INSERT INTO dbo.subscriptionplans
    (code, name, tagline, monthlyprice, yearlyprice, isfeatured, sortorder, entitlementcode, ishidden)
SELECT 'PRO_PARTNER', name, tagline, 0, 0, false, 100, 'PRO', true
FROM dbo.subscriptionplans
WHERE code = 'PRO'
  AND NOT EXISTS (SELECT 1 FROM dbo.subscriptionplans WHERE code = 'PRO_PARTNER');
