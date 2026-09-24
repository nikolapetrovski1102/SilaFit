USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Every App Store renewal is a new TransactionId under the same
-- OriginalTransactionId, so that is the key that says which Silen account a
-- subscription belongs to. usp_SubscriptionReceipt_GetOwner reads it on every
-- verify/restore call to stop one store subscription unlocking several accounts.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'dbo.SubscriptionReceipts')
                 AND name = N'IX_SubscriptionReceipts_Store_OriginalTransaction')
BEGIN
    CREATE NONCLUSTERED INDEX IX_SubscriptionReceipts_Store_OriginalTransaction
        ON dbo.SubscriptionReceipts (Store, OriginalTransactionId)
        INCLUDE (UserId)
        WHERE OriginalTransactionId IS NOT NULL;
END
GO
