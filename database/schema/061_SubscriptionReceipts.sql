USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Append-only ledger of every verified store receipt/transaction. The unique
-- constraint on (Store, TransactionId) is what makes the client-triggered
-- verify call, the store webhooks, and the reconciliation job all safe to
-- run concurrently without ever double-crediting the same transaction.
IF OBJECT_ID(N'dbo.SubscriptionReceipts', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SubscriptionReceipts
    (
        ReceiptId               UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_SubscriptionReceipts_Id DEFAULT NEWSEQUENTIALID(),
        UserId                  UNIQUEIDENTIFIER NOT NULL,
        PlanId                  UNIQUEIDENTIFIER NOT NULL,
        Store                   NVARCHAR(10)     NOT NULL,
        ProductId               NVARCHAR(150)    NOT NULL,
        TransactionId           NVARCHAR(100)    NOT NULL,
        OriginalTransactionId   NVARCHAR(100)    NULL,
        PurchaseToken           NVARCHAR(MAX)    NULL,
        RawPayload              NVARCHAR(MAX)    NULL,
        Status                  NVARCHAR(20)     NOT NULL CONSTRAINT DF_SubscriptionReceipts_Status DEFAULT ('Active'),
        ExpiresAtUtc            DATETIME2(3)     NULL,
        AutoRenewing            BIT              NOT NULL CONSTRAINT DF_SubscriptionReceipts_AutoRenewing DEFAULT (0),
        VerifiedAtUtc           DATETIME2(3)     NOT NULL CONSTRAINT DF_SubscriptionReceipts_VerifiedAtUtc DEFAULT (SYSUTCDATETIME()),
        CreatedAtUtc            DATETIME2(3)     NOT NULL CONSTRAINT DF_SubscriptionReceipts_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_SubscriptionReceipts PRIMARY KEY CLUSTERED (ReceiptId),
        CONSTRAINT FK_SubscriptionReceipts_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT FK_SubscriptionReceipts_SubscriptionPlans FOREIGN KEY (PlanId) REFERENCES dbo.SubscriptionPlans(PlanId),
        CONSTRAINT CK_SubscriptionReceipts_Store CHECK (Store IN ('AppStore', 'PlayStore')),
        CONSTRAINT CK_SubscriptionReceipts_Status CHECK (Status IN ('Active', 'Expired', 'Cancelled', 'Refunded', 'Pending')),
        CONSTRAINT UQ_SubscriptionReceipts_Store_Transaction UNIQUE (Store, TransactionId)
    );

    CREATE INDEX IX_SubscriptionReceipts_User ON dbo.SubscriptionReceipts(UserId, CreatedAtUtc DESC);
    CREATE INDEX IX_SubscriptionReceipts_Reconciliation ON dbo.SubscriptionReceipts(Status, ExpiresAtUtc) INCLUDE (Store, TransactionId, PurchaseToken);
END
GO

-- Points UserSubscriptions at the receipt that most recently activated it,
-- and tracks whether the store still expects auto-renewal, so the
-- reconciliation job knows which receipts still need periodic re-checking.
IF COL_LENGTH(N'dbo.UserSubscriptions', N'LatestReceiptId') IS NULL
    ALTER TABLE dbo.UserSubscriptions ADD LatestReceiptId UNIQUEIDENTIFIER NULL
        CONSTRAINT FK_UserSubscriptions_SubscriptionReceipts REFERENCES dbo.SubscriptionReceipts(ReceiptId);
GO
IF COL_LENGTH(N'dbo.UserSubscriptions', N'AutoRenewing') IS NULL
    ALTER TABLE dbo.UserSubscriptions ADD AutoRenewing BIT NOT NULL CONSTRAINT DF_UserSubscriptions_AutoRenewing DEFAULT (0);
GO
