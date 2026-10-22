-- Silen-issued discount codes for Google Play. Play promo codes can only grant
-- free time, so a percentage discount is a developer-determined subscription
-- offer (tagged "promo-code" in Play Console) that the app only shows once the
-- server has accepted a code naming it. App Store discounts stay Apple offer
-- codes and never touch these tables.
--
-- How long the code can be entered is StartsAtUtc/ExpiresAtUtc here; how long
-- the discount lasts once bought is the offer's own pricing phase in Play.
CREATE TABLE dbo.promocodes (
    code varchar(40) COLLATE ci NOT NULL,
    playofferid varchar(100) COLLATE ci NOT NULL,
    startsatutc timestamp(3),
    expiresatutc timestamp(3),
    maxredemptions integer,
    isactive boolean DEFAULT true NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_promocodes PRIMARY KEY (code),
    CONSTRAINT ck_promocodes_maxredemptions CHECK (maxredemptions IS NULL OR maxredemptions > 0)
);

-- One row per account that entered a code, so MaxRedemptions counts people,
-- not attempts, and re-entering a code never uses up another redemption.
CREATE TABLE dbo.promocoderedemptions (
    code varchar(40) COLLATE ci NOT NULL,
    userid uuid NOT NULL,
    redeemedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_promocoderedemptions PRIMARY KEY (code, userid),
    CONSTRAINT fk_promocoderedemptions_promocodes FOREIGN KEY (code) REFERENCES dbo.promocodes (code) ON DELETE CASCADE,
    CONSTRAINT fk_promocoderedemptions_users FOREIGN KEY (userid) REFERENCES dbo.users (userid) ON DELETE CASCADE
);
