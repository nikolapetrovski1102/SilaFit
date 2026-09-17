using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>The imported long-form diet guides (dbo.DietPlans). Read-only: these are
/// shipped reference articles, not user-editable plans. Distinct from
/// <see cref="IDietPlanService"/>, which serves the day-by-day meal-schedule feature.</summary>
public interface IDietGuideService
{
    Task<ServiceResult<List<DietGuideModel>>> GetAllAsync(CancellationToken cancellationToken = default);

    Task<ServiceResult<DietGuideDetailDto>> GetDetailAsync(Guid dietGuideId, CancellationToken cancellationToken = default);
}
