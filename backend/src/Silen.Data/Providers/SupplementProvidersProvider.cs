using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

/// <inheritdoc cref="ISupplementProvidersProvider"/>
public sealed class SupplementProvidersProvider(ISqlExecutor sqlExecutor) : ISupplementProvidersProvider
{
    public Task<List<SupplementProviderModel>> GetActiveAsync(CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_SupplementProviders_GetActive",
            [],
            reader => SqlResultSetReader.ReadListAsync(reader, TrainerDocumentRowMapper.MapProvider, cancellationToken),
            cancellationToken);

    public Task<List<AdminSupplementProviderModel>> GetAllAsync(CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_SupplementProviders_GetAll",
            [],
            reader => SqlResultSetReader.ReadListAsync(reader, TrainerDocumentRowMapper.MapAdminProvider, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> UpsertAsync(AdminSupplementProviderUpsertRequest request, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_SupplementProvider_Upsert",
            [
                SqlParameterBuilder.Create("@ProviderId", request.ProviderId),
                SqlParameterBuilder.Create("@Name", request.Name),
                SqlParameterBuilder.Create("@Tagline", request.Tagline),
                SqlParameterBuilder.Create("@LogoUrl", request.LogoUrl),
                SqlParameterBuilder.Create("@PromoCode", request.PromoCode),
                SqlParameterBuilder.Create("@DiscountLabel", request.DiscountLabel),
                SqlParameterBuilder.Create("@ShopUrl", request.ShopUrl),
                SqlParameterBuilder.Create("@Category", request.Category),
                SqlParameterBuilder.Create("@IsActive", request.IsActive),
                SqlParameterBuilder.Create("@SortOrder", request.SortOrder),
                .. AdminActorParameters.Build(actor)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);

    public Task<AdminMutationResultModel> DeleteAsync(Guid providerId, AdminActorModel actor, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Admin_SupplementProvider_Delete",
            [SqlParameterBuilder.Create("@ProviderId", providerId), .. AdminActorParameters.Build(actor)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, AdminContentRowMapper.MapMutation, cancellationToken),
            cancellationToken);
}
