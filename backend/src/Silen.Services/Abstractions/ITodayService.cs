using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

public interface ITodayService
{
    /// <summary>Composes Hydration + Bodyweight + Streak + WorkoutSession + Splits into the Today dashboard - the one fully-wired vertical slice.</summary>
    Task<ServiceResult<TodayDashboardDto>> GetDashboardAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<ServiceResult<int>> LogHydrationAsync(Guid userId, LogHydrationRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<LogBodyweightResultDto>> LogBodyweightAsync(Guid userId, LogBodyweightRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<WorkoutSessionCompletionModel>> CompleteWorkoutAsync(Guid userId, CompleteWorkoutRequest request, CancellationToken cancellationToken = default);

    /// <summary>Every set logged for the session scheduled on <paramref name="date"/> - powers Home's "View set history" button.</summary>
    Task<ServiceResult<List<SetLogDto>>> GetWorkoutHistoryAsync(Guid userId, DateTime date, CancellationToken cancellationToken = default);
}
