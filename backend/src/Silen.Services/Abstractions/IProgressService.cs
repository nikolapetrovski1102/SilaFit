using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

public interface IProgressService
{
    /// <summary>Real numbers from logged data + a rule-based (template-driven) narrative. No external AI call.</summary>
    Task<ServiceResult<ProgressOverviewDto>> GetOverviewAsync(Guid userId, int days, CancellationToken cancellationToken = default);

    /// <summary>The heaviest set ever logged per exercise, most recently achieved first.</summary>
    Task<ServiceResult<List<PersonalRecordDto>>> GetPersonalRecordsAsync(Guid userId, int top, CancellationToken cancellationToken = default);

    /// <summary>Every exercise the caller has logged sets for. PRO/Advanced only; throws
    /// <see cref="Silen.Common.Exceptions.ProUpgradeRequiredException"/> otherwise.</summary>
    Task<ServiceResult<List<TrackedExerciseDto>>> GetTrackedExercisesAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Per-session history of one exercise over the last <paramref name="days"/> days. PRO/Advanced only;
    /// throws <see cref="Silen.Common.Exceptions.ProUpgradeRequiredException"/> otherwise.</summary>
    Task<ServiceResult<ExerciseProgressDto>> GetExerciseProgressAsync(Guid userId, Guid exerciseId, int days, CancellationToken cancellationToken = default);

    /// <summary>Grants a Free caller a short Progress pass after a rewarded video ad. Throws
    /// <see cref="Silen.Common.Exceptions.TooManyRequestsException"/> once the daily cap is used;
    /// a Pro/Advanced caller gets a pass with no expiry and nothing recorded.</summary>
    Task<ServiceResult<ProgressAdPassDto>> GrantAdPassAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Ends the caller's Progress ad pass early - the app calls it when the user leaves the screen.</summary>
    Task<ServiceResult<bool>> EndAdPassAsync(Guid userId, CancellationToken cancellationToken = default);
}
