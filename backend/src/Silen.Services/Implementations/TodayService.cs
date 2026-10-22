using Microsoft.Extensions.Logging;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="ITodayService"/>
/// <remarks>The one fully-wired vertical slice: composes five Providers into a single dashboard payload.</remarks>
public sealed class TodayService(
    IWorkoutSessionProvider workoutSessionProvider,
    IHydrationProvider hydrationProvider,
    IBodyweightProvider bodyweightProvider,
    IStreakProvider streakProvider,
    IUserSettingsProvider userSettingsProvider,
    ISplitsProvider splitsProvider,
    IUserProfileProvider userProfileProvider,
    IMealPlanningService mealPlanningService,
    ISubscriptionGate subscriptionGate,
    ILogger<TodayService> logger) : ITodayService
{
    public Task<ServiceResult<TodayDashboardDto>> GetDashboardAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            // These six reads are independent, so run them concurrently instead of
            // serially. The dashboard used to pay the sum of six round-trips on the
            // hottest endpoint; the pool gives each call its own connection, so this
            // drops the latency to roughly the slowest one. Task.WhenAll also
            // observes every task, so a failure still surfaces to ServiceExecutor.
            var sessionTask = workoutSessionProvider.GetTodayScheduledAsync(userId, cancellationToken);
            var hydrationTask = hydrationProvider.GetTodayTotalAsync(userId, cancellationToken);
            var settingsTask = userSettingsProvider.GetAsync(userId, cancellationToken);
            var weightsTask = bodyweightProvider.GetLatestAsync(userId, cancellationToken);
            var streakTask = streakProvider.GetStatusAsync(userId, cancellationToken);
            var activeSplitTask = splitsProvider.GetActiveAsync(userId, cancellationToken);

            await Task.WhenAll(sessionTask, hydrationTask, settingsTask, weightsTask, streakTask, activeSplitTask)
                .ConfigureAwait(false);

            var (session, exercises) = await sessionTask.ConfigureAwait(false);
            var hydrationTotal = await hydrationTask.ConfigureAwait(false);
            var settings = await settingsTask.ConfigureAwait(false);
            var weights = await weightsTask.ConfigureAwait(false);
            var (streakStatus, week) = await streakTask.ConfigureAwait(false);
            var activeSplit = await activeSplitTask.ConfigureAwait(false);

            return new TodayDashboardDto
            {
                Session = new TodaySessionDto
                {
                    WorkoutSessionId = session?.WorkoutSessionId,
                    Status = session?.Status ?? "Scheduled",
                    Title = session?.Title,
                    FocusLabel = session?.FocusLabel,
                    EstimatedMinutes = session?.EstimatedMinutes,
                    IsRestDay = session?.IsRestDay ?? session is null
                },
                TargetExercises = exercises.Select(e => new TargetExerciseDto
                {
                    ExerciseId = e.ExerciseId,
                    Name = e.Name,
                    MuscleGroup = e.MuscleGroup,
                    EquipmentType = e.EquipmentType,
                    DemoVideoUrl = e.DemoVideoUrl,
                    TargetSets = e.TargetSets,
                    TargetRepsLow = e.TargetRepsLow,
                    TargetRepsHigh = e.TargetRepsHigh
                }).ToList(),
                HydrationTotalMl = hydrationTotal,
                HydrationTargetMl = settings?.TargetWaterMl ?? 3500,
                LatestWeightKg = weights.Count > 0 ? weights[0].WeightKg : null,
                WeightDeltaKg = weights.Count > 1 ? weights[0].WeightKg - weights[1].WeightKg : null,
                CurrentStreakDays = streakStatus.CurrentStreakDays,
                WeeklyCompliancePercent = streakStatus.WeeklyCompliancePercent,
                WeekStatuses = week.Select(w => new WeekDayStatusDto
                {
                    Date = w.SessionDate,
                    Status = w.SessionStatus ?? "Scheduled"
                }).ToList(),
                ActiveSplit = activeSplit is null ? null : new ActiveSplitDto
                {
                    SplitId = activeSplit.SplitId,
                    Name = activeSplit.Name,
                    DurationDays = activeSplit.DurationDays,
                    ActivatedAtUtc = activeSplit.ActivatedAtUtc
                }
            };
        });

    public Task<ServiceResult<int>> LogHydrationAsync(Guid userId, LogHydrationRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (request.AmountMl <= 0)
            {
                throw new ValidationException("Hydration amount must be positive.", "Enter an amount greater than zero.");
            }

            return await hydrationProvider.LogAsync(userId, request.AmountMl, cancellationToken);
        });

    public Task<ServiceResult<LogBodyweightResultDto>> LogBodyweightAsync(Guid userId, LogBodyweightRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (request.WeightKg <= 0)
            {
                throw new ValidationException("Bodyweight must be positive.", "Enter a valid bodyweight.");
            }

            var entries = await bodyweightProvider.LogAsync(
                userId, request.WeightKg, request.BodyweightLogId, ClampClientTimestamp(request.LoggedAtUtc), cancellationToken);

            // usp_Bodyweight_Log updates UserProfiles.WeightKg in the same
            // database call. Refresh non-manual nutrition targets from that
            // updated profile so calorie and macro recommendations follow the
            // user's actual latest entry rather than their onboarding weight.
            try
            {
                var profile = await userProfileProvider.GetAsync(userId, cancellationToken);
                if (profile is not null)
                {
                    var targetResult = await mealPlanningService
                        .RecomputeTargetsAsync(userId, profile, cancellationToken)
                        .ConfigureAwait(false);
                    if (!targetResult.IsSuccess)
                    {
                        logger.LogWarning(
                            "Bodyweight was saved for user {UserId}, but automatic nutrition targets could not be refreshed: {Reason}",
                            userId,
                            targetResult.LogMessage);
                    }
                }
            }
            catch (Exception exception)
            {
                // The bodyweight write has already succeeded. Do not encourage
                // a retry that would create a duplicate log just because the
                // dependent target refresh had a transient failure.
                logger.LogWarning(
                    exception,
                    "Bodyweight was saved for user {UserId}, but automatic nutrition targets could not be refreshed.",
                    userId);
            }

            return new LogBodyweightResultDto
            {
                LatestWeightKg = entries[0].WeightKg,
                DeltaKg = entries.Count > 1 ? entries[0].WeightKg - entries[1].WeightKg : null
            };
        });

    public Task<ServiceResult<WorkoutSessionCompletionModel>> CompleteWorkoutAsync(Guid userId, CompleteWorkoutRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (request.DurationMinutes <= 0)
            {
                throw new ValidationException("Workout duration must be positive.", "Enter how long the workout took.");
            }

            var setLogs = request.SetLogs?.Select(s => new SetLogEntryModel
            {
                ExerciseId = s.ExerciseId,
                SetNumber = s.SetNumber,
                WeightKg = s.WeightKg,
                Reps = s.Reps
            }).ToList();

            var completedAtUtc = ClampClientTimestamp(request.CompletedAtUtc);
            var scheduledDateUtc = request.SplitDayId is null
                ? (DateTime?)null
                : ClampScheduledDate(request.ScheduledDateUtc, completedAtUtc ?? DateTime.UtcNow);

            return await workoutSessionProvider.CompleteAsync(
                userId, request.WorkoutSessionId, request.DurationMinutes,
                request.CaloriesEstimate, request.RpeScore, request.TonnageKg, setLogs,
                completedAtUtc, request.SplitDayId, scheduledDateUtc, cancellationToken)
                ?? throw new NotFoundException($"Workout session '{request.WorkoutSessionId}' not found for user '{userId}'.", "That workout session couldn't be found.");
        });

    /// <summary>
    /// The day an offline-made session was for: the day the workout ended, or the day before (a
    /// session started just before midnight). Anything else isn't trusted and becomes the day it
    /// ended.
    /// </summary>
    public static DateTime ClampScheduledDate(DateTime? clientDateUtc, DateTime completedAtUtc)
    {
        var endedOn = completedAtUtc.Date;
        if (clientDateUtc is not { } value)
        {
            return endedOn;
        }

        var date = value.Date;
        return date == endedOn || date == endedOn.AddDays(-1) ? date : endedOn;
    }

    /// <summary>How far back an offline-queued write may date itself. Older than this and the
    /// client clock (or a week-old queue) is not trusted - the server time is used instead.</summary>
    public static readonly TimeSpan MaxClientBackdate = TimeSpan.FromDays(7);

    /// <summary>
    /// A write uploaded from the phone's offline queue carries when it really happened, so a
    /// workout finished in a gym with no signal still counts for that day. Never trust it
    /// blindly: a future time becomes now, and anything older than <see cref="MaxClientBackdate"/>
    /// falls back to now (null) rather than letting a bad clock rewrite history.
    /// </summary>
    public static DateTime? ClampClientTimestamp(DateTime? clientUtc, DateTime? nowUtc = null)
    {
        if (clientUtc is not { } value)
        {
            return null;
        }

        var now = nowUtc ?? DateTime.UtcNow;
        var utc = value.Kind == DateTimeKind.Local ? value.ToUniversalTime() : DateTime.SpecifyKind(value, DateTimeKind.Utc);
        if (utc > now || utc < now - MaxClientBackdate)
        {
            return null;
        }

        return utc;
    }

    /// <summary>How far back a Free account can open a day's set history (the streak sheet
    /// and Home both link there); Pro/Advanced have no server-side limit.</summary>
    public const int FreeWorkoutHistoryDays = 14;

    public Task<ServiceResult<List<SetLogDto>>> GetWorkoutHistoryAsync(Guid userId, DateTime date, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            // `date` is the client's local calendar day, which can be a day behind UTC - one
            // extra day of slack keeps a Free user from being refused their own 14th day.
            var freeCutoff = DateTime.UtcNow.Date.AddDays(-(FreeWorkoutHistoryDays + 1));
            if (date.Date < freeCutoff
                && !await subscriptionGate.HasActiveProAsync(userId, cancellationToken).ConfigureAwait(false))
            {
                throw new ProUpgradeRequiredException($"User {userId} requested workout history older than {FreeWorkoutHistoryDays} days without an active Pro/Advanced subscription.");
            }

            var setLogs = await workoutSessionProvider.GetSetLogsByDateAsync(userId, date, cancellationToken);

            return setLogs.Select(s => new SetLogDto
            {
                ExerciseId = s.ExerciseId,
                ExerciseName = s.ExerciseName,
                SetNumber = s.SetNumber,
                WeightKg = s.WeightKg,
                Reps = s.Reps,
                CompletedAtUtc = s.CompletedAtUtc
            }).ToList();
        });

    public Task<ServiceResult<List<SetLogDto>>> GetExerciseHistoryAsync(Guid userId, Guid exerciseId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (!await subscriptionGate.HasActiveProAsync(userId, cancellationToken).ConfigureAwait(false))
            {
                throw new ProUpgradeRequiredException($"User {userId} requested exercise history without an active Pro/Advanced subscription.");
            }

            var setLogs = await workoutSessionProvider.GetExerciseHistoryAsync(userId, exerciseId, top: 5, cancellationToken);

            return setLogs.Select(s => new SetLogDto
            {
                ExerciseId = s.ExerciseId,
                ExerciseName = s.ExerciseName,
                SetNumber = s.SetNumber,
                WeightKg = s.WeightKg,
                Reps = s.Reps,
                CompletedAtUtc = s.CompletedAtUtc
            }).ToList();
        });
}
