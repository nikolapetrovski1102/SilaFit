using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

public interface IPlanService
{
    Task<ServiceResult<List<PlanCatalogEntryDto>>> GetCatalogAsync(CancellationToken cancellationToken = default);

    Task<ServiceResult<UserSubscriptionModel>> GetCurrentAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<ServiceResult<UserSubscriptionModel>> PurchaseAsync(Guid userId, PurchaseRequest request, CancellationToken cancellationToken = default);

    /// <summary>Verifies a completed native purchase against the matching store's server API
    /// and, if active, grants the plan resolved from the verified product id.</summary>
    Task<ServiceResult<UserSubscriptionModel>> VerifyPurchaseAsync(
        Guid userId, VerifyPurchaseRequest request, CancellationToken cancellationToken = default);
}
