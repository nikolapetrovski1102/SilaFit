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
    ISplitsProvider splitsProvider) : ITodayService
{
    public Task<ServiceResult<TodayDashboardDto>> GetDashboardAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (session, exercises) = await workoutSessionProvider.GetTodayScheduledAsync(userId, cancellationToken);
            var hydrationTotal = await hydrationProvider.GetTodayTotalAsync(userId, cancellationToken);
            var settings = await userSettingsProvider.GetAsync(userId, cancellationToken);
            var weights = await bodyweightProvider.GetLatestAsync(userId, cancellationToken);
            var (streakStatus, week) = await streakProvider.GetStatusAsync(userId, cancellationToken);
            var activeSplit = await splitsProvider.GetActiveAsync(userId, cancellationToken);

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

            var entries = await bodyweightProvider.LogAsync(userId, request.WeightKg, cancellationToken);

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

            return await workoutSessionProvider.CompleteAsync(
                userId, request.WorkoutSessionId, request.DurationMinutes,
                request.CaloriesEstimate, request.RpeScore, request.TonnageKg, cancellationToken)
                ?? throw new NotFoundException($"Workout session '{request.WorkoutSessionId}' not found for user '{userId}'.", "That workout session couldn't be found.");
        });
}
