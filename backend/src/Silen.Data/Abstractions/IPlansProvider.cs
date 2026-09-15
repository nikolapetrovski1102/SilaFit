using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IPlansProvider
{
    Task<(List<SubscriptionPlanModel> Plans, List<PlanFeatureModel> Features)> GetAllAsync(CancellationToken cancellationToken = default);

    Task<UserSubscriptionModel?> PurchaseAsync(
        Guid userId, Guid planId, string billingCycle, CancellationToken cancellationToken = default);

    Task<UserSubscriptionModel?> GetActiveAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Every currently entitled subscriber of a plan (by code), with contact details -
    /// used by the monthly review batch to reach all paying users of a tier.</summary>
    Task<List<PlanSubscriberModel>> GetActiveSubscribersByPlanCodeAsync(
        string planCode, CancellationToken cancellationToken = default);

    /// <summary>The complement: active users with an email who are not currently entitled to a
    /// paid plan - the monthly review teaser audience.</summary>
    Task<List<PlanSubscriberModel>> GetNonSubscribersAsync(CancellationToken cancellationToken = default);
}
