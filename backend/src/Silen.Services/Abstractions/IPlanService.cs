using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

public interface IPlanService
{
    Task<ServiceResult<List<PlanCatalogEntryDto>>> GetCatalogAsync(CancellationToken cancellationToken = default);

    Task<ServiceResult<UserSubscriptionModel>> PurchaseAsync(Guid userId, PurchaseRequest request, CancellationToken cancellationToken = default);
}
