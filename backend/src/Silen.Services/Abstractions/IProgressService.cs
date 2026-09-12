using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

public interface IProgressService
{
    /// <summary>Real numbers from logged data + a rule-based (template-driven) narrative. No external AI call.</summary>
    Task<ServiceResult<ProgressOverviewDto>> GetOverviewAsync(Guid userId, int days, CancellationToken cancellationToken = default);
}
