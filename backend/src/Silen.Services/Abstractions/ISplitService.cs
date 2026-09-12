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

    /// <summary>Picks a split for a user who doesn't have one active yet, matching their onboarding
    /// goal, and activates it. A no-op (returns null Data, still a success result) when the user
    /// already has an active split - this never overrides a choice the user already made, only
    /// fills in a first-time default - or when no split is tagged for <paramref name="goal"/>.</summary>
    Task<ServiceResult<ActiveSplitModel?>> AutoAssignRecommendedAsync(Guid userId, string? goal, CancellationToken cancellationToken = default);
}
