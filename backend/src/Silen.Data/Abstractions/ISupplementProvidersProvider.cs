using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>Partner shops with discount codes (SupplementProviders.sql).</summary>
public interface ISupplementProvidersProvider
{
    Task<List<SupplementProviderModel>> GetActiveAsync(CancellationToken cancellationToken = default);

    Task<List<AdminSupplementProviderModel>> GetAllAsync(CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> UpsertAsync(AdminSupplementProviderUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default);

    Task<AdminMutationResultModel> DeleteAsync(Guid providerId, AdminActorModel actor, CancellationToken cancellationToken = default);
}
