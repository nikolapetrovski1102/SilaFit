using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

public interface ISplitService
{
    /// <param name="userId">The caller's id if authenticated (guests included), so recommended
    /// splits can be flagged against their onboarding goal; null marks every split unmatched.</param>
    Task<ServiceResult<List<WorkoutSplitModel>>> GetAllAsync(Guid? userId, CancellationToken cancellationToken = default);

    Task<ServiceResult<SplitDetailDto>> GetDetailAsync(Guid splitId, CancellationToken cancellationToken = default);

    Task<ServiceResult<ActiveSplitModel>> ActivateAsync(Guid userId, ActivateSplitRequest request, CancellationToken cancellationToken = default);
}
