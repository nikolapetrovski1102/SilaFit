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
}
