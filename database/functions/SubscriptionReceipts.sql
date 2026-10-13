-- Upsert keyed on (Store, TransactionId) so the client-triggered verify call,
-- the store webhooks, and the reconciliation job can all write the same
-- transaction concurrently without creating duplicate receipts.
CREATE OR REPLACE FUNCTION dbo.usp_subscriptionreceipt_insert(
    p_userid uuid,
    p_planid uuid,
    p_store varchar(10),
    p_productid varchar(150),
    p_transactionid varchar(100),
    p_originaltransactionid varchar(100) DEFAULT NULL,
    p_purchasetoken text DEFAULT NULL,
    p_rawpayload text DEFAULT NULL,
    p_status varchar(20) DEFAULT NULL,
    p_expiresatutc timestamp(3) DEFAULT NULL,
    p_autorenewing boolean DEFAULT false
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    INSERT INTO dbo.subscriptionreceipts (userid, planid, store, productid, transactionid, originaltransactionid,
                                          purchasetoken, rawpayload, status, expiresatutc, autorenewing)
    VALUES (p_userid, p_planid, p_store, p_productid, p_transactionid, p_originaltransactionid,
            p_purchasetoken, p_rawpayload, p_status, p_expiresatutc, p_autorenewing)
    ON CONFLICT (store, transactionid) DO UPDATE SET
        planid = p_planid, productid = p_productid,
        originaltransactionid = p_originaltransactionid, purchasetoken = p_purchasetoken,
        rawpayload = p_rawpayload, status = p_status, expiresatutc = p_expiresatutc,
        autorenewing = p_autorenewing, verifiedatutc = dbo.sysutcdatetime();

    OPEN c1 FOR
    SELECT receiptid, userid, planid, store, productid, transactionid, originaltransactionid,
           purchasetoken, rawpayload, status, expiresatutc, autorenewing, verifiedatutc, createdatutc
    FROM dbo.subscriptionreceipts
    WHERE store = p_store AND transactionid = p_transactionid;
    RETURN NEXT c1;
END $$;

-- The verified-data replacement for the placeholder usp_Subscription_Purchase:
-- p_planid here must already have been resolved from the store's verified
-- productId, never from a client-supplied plan choice.
CREATE OR REPLACE FUNCTION dbo.usp_subscription_activatefromreceipt(
    p_userid uuid,
    p_planid uuid,
    p_billingcycle varchar(10),
    p_expiresatutc timestamp(3),
    p_receiptid uuid,
    p_autorenewing boolean DEFAULT false
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    INSERT INTO dbo.usersubscriptions (userid, planid, billingcycle, status, startedatutc, expiresatutc, latestreceiptid, autorenewing)
    VALUES (p_userid, p_planid, p_billingcycle, 'Active', dbo.sysutcdatetime(), p_expiresatutc, p_receiptid, p_autorenewing)
    ON CONFLICT (userid) DO UPDATE SET
        planid = p_planid, billingcycle = p_billingcycle, status = 'Active',
        startedatutc = dbo.sysutcdatetime(), expiresatutc = p_expiresatutc,
        latestreceiptid = p_receiptid, autorenewing = p_autorenewing;

    OPEN c1 FOR
    SELECT userid, planid, billingcycle, status, startedatutc, expiresatutc, latestreceiptid, autorenewing
    FROM dbo.usersubscriptions
    WHERE userid = p_userid;
    RETURN NEXT c1;
END $$;

-- Looks up a single receipt by its natural key - what a store webhook/notification
-- identifies a transaction by - so ApplyStoreNotificationAsync can find which
-- user/plan it belongs to before re-verifying and re-activating.
CREATE OR REPLACE FUNCTION dbo.usp_subscriptionreceipt_getbystoretransaction(
    p_store varchar(10),
    p_transactionid varchar(100)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT receiptid, userid, planid, store, productid, transactionid, originaltransactionid,
           purchasetoken, rawpayload, status, expiresatutc, autorenewing, verifiedatutc, createdatutc
    FROM dbo.subscriptionreceipts
    WHERE store = p_store AND transactionid = p_transactionid;
    RETURN NEXT c1;
END $$;

-- Looks up a single receipt by its Play purchase token - what a Google
-- Pub/Sub Real-time Developer Notification identifies a transaction by
-- (it never carries the order id SubscriptionReceipts.TransactionId is
-- keyed on for PlayStore rows), so the webhook can resolve which
-- transaction to re-verify.
CREATE OR REPLACE FUNCTION dbo.usp_subscriptionreceipt_getbypurchasetoken(
    p_purchasetoken text
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT receiptid, userid, planid, store, productid, transactionid, originaltransactionid,
           purchasetoken, rawpayload, status, expiresatutc, autorenewing, verifiedatutc, createdatutc
    FROM dbo.subscriptionreceipts
    WHERE store = 'PlayStore' AND purchasetoken = p_purchasetoken
    ORDER BY verifiedatutc DESC
    LIMIT 1;
    RETURN NEXT c1;
END $$;

-- Finds the Silen account a store subscription already belongs to - by
-- OriginalTransactionId for the App Store (shared by every renewal) or by
-- purchase token for Play (stable across renewals). The verify endpoint uses
-- it to refuse activating one store subscription on a second account.
CREATE OR REPLACE FUNCTION dbo.usp_subscriptionreceipt_getowner(
    p_store varchar(10),
    p_originaltransactionid varchar(100) DEFAULT NULL,
    p_purchasetoken text DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT receiptid, userid, planid, store, productid, transactionid, originaltransactionid,
           purchasetoken, rawpayload, status, expiresatutc, autorenewing, verifiedatutc, createdatutc
    FROM dbo.subscriptionreceipts
    WHERE store = p_store
      AND ((p_originaltransactionid IS NOT NULL AND originaltransactionid = p_originaltransactionid)
        OR (p_purchasetoken IS NOT NULL AND purchasetoken = p_purchasetoken))
    ORDER BY createdatutc ASC
    LIMIT 1;
    RETURN NEXT c1;
END $$;

-- Moves a subscription out of Active (Cancelled/Expired) without touching
-- which plan/receipt it's tied to - used when a webhook/reconciliation check
-- finds the store no longer considers the receipt current.
CREATE OR REPLACE FUNCTION dbo.usp_subscription_setstatus(
    p_userid uuid,
    p_status varchar(20)
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.usersubscriptions
    SET status = p_status
    WHERE userid = p_userid;
END $$;

-- Active, auto-renewing receipts due for a store re-check, oldest-verified
-- first, for the periodic reconciliation job (Silen.Tools.SubscriptionSync).
-- Non-renewing/terminal receipts (Expired, Cancelled, Refunded) never need
-- re-checking, so they're excluded rather than just deprioritized.
CREATE OR REPLACE FUNCTION dbo.usp_subscriptionreceipt_getforreconciliation(
    p_batchsize integer DEFAULT 200
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT r.receiptid, r.userid, r.planid, r.store, r.productid, r.transactionid,
           r.originaltransactionid, r.purchasetoken, r.status, r.expiresatutc,
           r.autorenewing, r.verifiedatutc
    FROM dbo.subscriptionreceipts r
    WHERE r.status = 'Active'
      AND r.autorenewing
    ORDER BY r.verifiedatutc ASC
    LIMIT p_batchsize;
    RETURN NEXT c1;
END $$;
