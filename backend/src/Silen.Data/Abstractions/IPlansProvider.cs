using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IPlansProvider
{
    Task<(List<SubscriptionPlanModel> Plans, List<PlanFeatureModel> Features)> GetAllAsync(CancellationToken cancellationToken = default);

    Task<UserSubscriptionModel?> PurchaseAsync(
        Guid userId, Guid planId, string billingCycle, CancellationToken cancellationToken = default);

    Task<UserSubscriptionModel?> GetActiveAsync(Guid userId, CancellationToken cancellationToken = default);
}
