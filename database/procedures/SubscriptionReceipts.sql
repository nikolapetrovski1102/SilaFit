USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Upsert keyed on (Store, TransactionId) so the client-triggered verify call,
-- the store webhooks, and the reconciliation job can all write the same
-- transaction concurrently without creating duplicate receipts.
CREATE OR ALTER PROCEDURE dbo.usp_SubscriptionReceipt_Insert
    @UserId UNIQUEIDENTIFIER,
    @PlanId UNIQUEIDENTIFIER,
    @Store NVARCHAR(10),
    @ProductId NVARCHAR(150),
    @TransactionId NVARCHAR(100),
    @OriginalTransactionId NVARCHAR(100) = NULL,
    @PurchaseToken NVARCHAR(MAX) = NULL,
    @RawPayload NVARCHAR(MAX) = NULL,
    @Status NVARCHAR(20),
    @ExpiresAtUtc DATETIME2(3) = NULL,
    @AutoRenewing BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.SubscriptionReceipts AS target
    USING (SELECT @Store AS Store, @TransactionId AS TransactionId) AS source
    ON target.Store = source.Store AND target.TransactionId = source.TransactionId
    WHEN MATCHED THEN
        UPDATE SET PlanId = @PlanId, ProductId = @ProductId,
                   OriginalTransactionId = @OriginalTransactionId, PurchaseToken = @PurchaseToken,
                   RawPayload = @RawPayload, Status = @Status, ExpiresAtUtc = @ExpiresAtUtc,
                   AutoRenewing = @AutoRenewing, VerifiedAtUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (UserId, PlanId, Store, ProductId, TransactionId, OriginalTransactionId,
                PurchaseToken, RawPayload, Status, ExpiresAtUtc, AutoRenewing)
        VALUES (@UserId, @PlanId, @Store, @ProductId, @TransactionId, @OriginalTransactionId,
                @PurchaseToken, @RawPayload, @Status, @ExpiresAtUtc, @AutoRenewing);

    SELECT ReceiptId, UserId, PlanId, Store, ProductId, TransactionId, OriginalTransactionId,
           PurchaseToken, RawPayload, Status, ExpiresAtUtc, AutoRenewing, VerifiedAtUtc, CreatedAtUtc
    FROM dbo.SubscriptionReceipts
    WHERE Store = @Store AND TransactionId = @TransactionId;
END
GO

-- The verified-data replacement for the placeholder usp_Subscription_Purchase:
-- @PlanId here must already have been resolved from the store's verified
-- productId, never from a client-supplied plan choice.
CREATE OR ALTER PROCEDURE dbo.usp_Subscription_ActivateFromReceipt
    @UserId UNIQUEIDENTIFIER,
    @PlanId UNIQUEIDENTIFIER,
    @BillingCycle NVARCHAR(10),
    @ExpiresAtUtc DATETIME2(3),
    @ReceiptId UNIQUEIDENTIFIER,
    @AutoRenewing BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.UserSubscriptions AS target
    USING (SELECT @UserId AS UserId) AS source
    ON target.UserId = source.UserId
    WHEN MATCHED THEN
        UPDATE SET PlanId = @PlanId, BillingCycle = @BillingCycle, Status = 'Active',
                   StartedAtUtc = SYSUTCDATETIME(), ExpiresAtUtc = @ExpiresAtUtc,
                   LatestReceiptId = @ReceiptId, AutoRenewing = @AutoRenewing
    WHEN NOT MATCHED THEN
        INSERT (UserId, PlanId, BillingCycle, Status, StartedAtUtc, ExpiresAtUtc, LatestReceiptId, AutoRenewing)
        VALUES (@UserId, @PlanId, @BillingCycle, 'Active', SYSUTCDATETIME(), @ExpiresAtUtc, @ReceiptId, @AutoRenewing);

    SELECT UserId, PlanId, BillingCycle, Status, StartedAtUtc, ExpiresAtUtc, LatestReceiptId, AutoRenewing
    FROM dbo.UserSubscriptions
    WHERE UserId = @UserId;
END
GO

-- Looks up a single receipt by its natural key - what a store webhook/notification
-- identifies a transaction by - so ApplyStoreNotificationAsync can find which
-- user/plan it belongs to before re-verifying and re-activating.
CREATE OR ALTER PROCEDURE dbo.usp_SubscriptionReceipt_GetByStoreTransaction
    @Store NVARCHAR(10),
    @TransactionId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ReceiptId, UserId, PlanId, Store, ProductId, TransactionId, OriginalTransactionId,
           PurchaseToken, RawPayload, Status, ExpiresAtUtc, AutoRenewing, VerifiedAtUtc, CreatedAtUtc
    FROM dbo.SubscriptionReceipts
    WHERE Store = @Store AND TransactionId = @TransactionId;
END
GO

-- Looks up a single receipt by its Play purchase token - what a Google
-- Pub/Sub Real-time Developer Notification identifies a transaction by
-- (it never carries the order id SubscriptionReceipts.TransactionId is
-- keyed on for PlayStore rows), so the webhook can resolve which
-- transaction to re-verify.
CREATE OR ALTER PROCEDURE dbo.usp_SubscriptionReceipt_GetByPurchaseToken
    @PurchaseToken NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1) ReceiptId, UserId, PlanId, Store, ProductId, TransactionId, OriginalTransactionId,
           PurchaseToken, RawPayload, Status, ExpiresAtUtc, AutoRenewing, VerifiedAtUtc, CreatedAtUtc
    FROM dbo.SubscriptionReceipts
    WHERE Store = 'PlayStore' AND PurchaseToken = @PurchaseToken
    ORDER BY VerifiedAtUtc DESC;
END
GO

-- Moves a subscription out of Active (Cancelled/Expired) without touching
-- which plan/receipt it's tied to - used when a webhook/reconciliation check
-- finds the store no longer considers the receipt current.
CREATE OR ALTER PROCEDURE dbo.usp_Subscription_SetStatus
    @UserId UNIQUEIDENTIFIER,
    @Status NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.UserSubscriptions
    SET Status = @Status
    WHERE UserId = @UserId;
END
GO

-- Active, auto-renewing receipts due for a store re-check, oldest-verified
-- first, for the periodic reconciliation job (Silen.Tools.SubscriptionSync).
-- Non-renewing/terminal receipts (Expired, Cancelled, Refunded) never need
-- re-checking, so they're excluded rather than just deprioritized.
CREATE OR ALTER PROCEDURE dbo.usp_SubscriptionReceipt_GetForReconciliation
    @BatchSize INT = 200
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@BatchSize)
        r.ReceiptId, r.UserId, r.PlanId, r.Store, r.ProductId, r.TransactionId,
        r.OriginalTransactionId, r.PurchaseToken, r.Status, r.ExpiresAtUtc,
        r.AutoRenewing, r.VerifiedAtUtc
    FROM dbo.SubscriptionReceipts r
    WHERE r.Status = 'Active'
      AND r.AutoRenewing = 1
    ORDER BY r.VerifiedAtUtc ASC;
END
GO
