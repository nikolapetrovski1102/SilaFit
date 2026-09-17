using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IDietGuideService"/>
public sealed class DietGuideService(IDietGuidesProvider dietGuidesProvider) : IDietGuideService
{
    public Task<ServiceResult<List<DietGuideModel>>> GetAllAsync(CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(() => dietGuidesProvider.GetAllAsync(cancellationToken));

    public Task<ServiceResult<DietGuideDetailDto>> GetDetailAsync(Guid dietGuideId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (guide, sections) = await dietGuidesProvider.GetDetailAsync(dietGuideId, cancellationToken);

            if (guide is null)
            {
                throw new NotFoundException(
                    $"Diet guide '{dietGuideId}' was not found.",
                    "That diet guide couldn't be found.");
            }

            return new DietGuideDetailDto
            {
                Guide = guide,
                Sections = sections.OrderBy(section => section.SortOrder).ToList()
            };
        });
}
