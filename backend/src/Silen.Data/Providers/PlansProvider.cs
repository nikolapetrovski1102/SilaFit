using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class PlansProvider(ISqlExecutor sqlExecutor) : IPlansProvider
{
    public Task<(List<SubscriptionPlanModel> Plans, List<PlanFeatureModel> Features)> GetAllAsync(
        CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Plans_GetAll",
            [],
            async reader =>
            {
                var plans = await SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapPlan, cancellationToken);
                await reader.NextResultAsync(cancellationToken);
                var features = await SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapPlanFeature, cancellationToken);
                return (plans, features);
            },
            cancellationToken);

    public Task<UserSubscriptionModel?> PurchaseAsync(
        Guid userId, Guid planId, string billingCycle, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Subscription_Purchase",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@PlanId", planId),
                SqlParameterBuilder.Create("@BillingCycle", billingCycle)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapSubscription, cancellationToken),
            cancellationToken);

    public Task<UserSubscriptionModel?> GetActiveAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Subscription_GetActive",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapSubscription, cancellationToken),
            cancellationToken);

    public Task<List<PlanSubscriberModel>> GetActiveSubscribersByPlanCodeAsync(
        string planCode, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Plans_GetActiveSubscribers",
            [SqlParameterBuilder.Create("@PlanCode", planCode)],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapPlanSubscriber, cancellationToken),
            cancellationToken);

    public Task<List<PlanSubscriberModel>> GetNonSubscribersAsync(CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Plans_GetNonSubscribers",
            [],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapPlanSubscriber, cancellationToken),
            cancellationToken);

    public Task<PlanEntitlementsModel?> GetEntitlementsForUserAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Plans_GetEntitlementsForUser",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapPlanEntitlements, cancellationToken),
            cancellationToken);

    public Task<SubscriptionReceiptModel?> InsertReceiptAsync(
        Guid userId, Guid planId, string store, string productId, string transactionId,
        string? originalTransactionId, string? purchaseToken, string? rawPayload,
        string status, DateTime? expiresAtUtc, bool autoRenewing, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_SubscriptionReceipt_Insert",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@PlanId", planId),
                SqlParameterBuilder.Create("@Store", store),
                SqlParameterBuilder.Create("@ProductId", productId),
                SqlParameterBuilder.Create("@TransactionId", transactionId),
                SqlParameterBuilder.Create("@OriginalTransactionId", originalTransactionId),
                SqlParameterBuilder.Create("@PurchaseToken", purchaseToken),
                SqlParameterBuilder.Create("@RawPayload", rawPayload),
                SqlParameterBuilder.Create("@Status", status),
                SqlParameterBuilder.Create("@ExpiresAtUtc", expiresAtUtc),
                SqlParameterBuilder.Create("@AutoRenewing", autoRenewing)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapReceipt, cancellationToken),
            cancellationToken);

    public Task<UserSubscriptionModel?> ActivateFromReceiptAsync(
        Guid userId, Guid planId, string billingCycle, DateTime expiresAtUtc,
        Guid receiptId, bool autoRenewing, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Subscription_ActivateFromReceipt",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@PlanId", planId),
                SqlParameterBuilder.Create("@BillingCycle", billingCycle),
                SqlParameterBuilder.Create("@ExpiresAtUtc", expiresAtUtc),
                SqlParameterBuilder.Create("@ReceiptId", receiptId),
                SqlParameterBuilder.Create("@AutoRenewing", autoRenewing)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapSubscription, cancellationToken),
            cancellationToken);

    public Task<List<SubscriptionReceiptModel>> GetReceiptsForReconciliationAsync(
        int batchSize = 200, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_SubscriptionReceipt_GetForReconciliation",
            [SqlParameterBuilder.Create("@BatchSize", batchSize)],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapReceipt, cancellationToken),
            cancellationToken);

    public Task<SubscriptionReceiptModel?> GetReceiptByStoreTransactionAsync(
        string store, string transactionId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_SubscriptionReceipt_GetByStoreTransaction",
            [
                SqlParameterBuilder.Create("@Store", store),
                SqlParameterBuilder.Create("@TransactionId", transactionId)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapReceipt, cancellationToken),
            cancellationToken);

    public Task<SubscriptionReceiptModel?> GetReceiptByPurchaseTokenAsync(
        string purchaseToken, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_SubscriptionReceipt_GetByPurchaseToken",
            [SqlParameterBuilder.Create("@PurchaseToken", purchaseToken)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapReceipt, cancellationToken),
            cancellationToken);

    public Task UpdateSubscriptionStatusAsync(Guid userId, string status, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_Subscription_SetStatus",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@Status", status)
            ],
            cancellationToken);
}
