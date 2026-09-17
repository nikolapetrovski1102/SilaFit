using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

/// <inheritdoc cref="IDietGuidesProvider"/>
public sealed class DietGuidesProvider(ISqlExecutor sqlExecutor) : IDietGuidesProvider
{
    public Task<List<DietGuideModel>> GetAllAsync(CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_DietGuides_GetAll",
            [],
            reader => SqlResultSetReader.ReadListAsync(reader, DietGuideRowMapper.MapGuide, cancellationToken),
            cancellationToken);

    public Task<(DietGuideModel? Guide, List<DietGuideSectionModel> Sections)> GetDetailAsync(
        Guid dietGuideId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_DietGuides_GetDetail",
            [SqlParameterBuilder.Create("@DietPlanId", dietGuideId)],
            async reader =>
            {
                var guide = await SqlResultSetReader.ReadSingleOrDefaultAsync(reader, DietGuideRowMapper.MapGuideDetail, cancellationToken);
                await reader.NextResultAsync(cancellationToken);
                var sections = await SqlResultSetReader.ReadListAsync(reader, DietGuideRowMapper.MapSection, cancellationToken);
                return (guide, sections);
            },
            cancellationToken);
}
