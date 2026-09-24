using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IProgressService"/>
public sealed class ProgressService(
    IWorkoutSessionProvider workoutSessionProvider,
    IStreakProvider streakProvider,
    ISubscriptionGate subscriptionGate) : IProgressService
{
    // Two years of sessions is far more than the chart can meaningfully plot,
    // and caps what a hand-crafted `days` can make the proc scan.
    private const int MaxExerciseProgressDays = 730;

    public Task<ServiceResult<ProgressOverviewDto>> GetOverviewAsync(Guid userId, int days, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var effectiveDays = days <= 0 ? 30 : days;
            var toDate = DateTime.UtcNow.Date;
            var fromDate = toDate.AddDays(-(effectiveDays - 1));

            var (summary, dayStatuses) = await workoutSessionProvider.GetRangeSummaryAsync(userId, fromDate, toDate, cancellationToken);
            var (streakStatus, _) = await streakProvider.GetStatusAsync(userId, cancellationToken);

            return new ProgressOverviewDto
            {
                CurrentStreakDays = streakStatus.CurrentStreakDays,
                WeeklyCompliancePercent = streakStatus.WeeklyCompliancePercent,
                CompletedSessions = summary.CompletedSessions,
                ScheduledSessions = summary.ScheduledSessions,
                TotalTonnageKg = summary.TotalTonnageKg,
                AvgRpe = summary.AvgRpe,
                Heatmap = dayStatuses.Select(d => new HeatmapDayDto
                {
                    Date = d.ScheduledDateUtc,
                    Status = d.Status,
                    TonnageKg = d.TonnageKg,
                    RpeScore = d.RpeScore
                }).ToList(),
                Insights = ProgressInsightGenerator.Generate(summary, streakStatus)
            };
        });

    public Task<ServiceResult<List<PersonalRecordDto>>> GetPersonalRecordsAsync(Guid userId, int top, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var effectiveTop = top <= 0 ? 5 : top;
            var records = await workoutSessionProvider.GetPersonalRecordsAsync(userId, effectiveTop, cancellationToken);

            return records.Select(r => new PersonalRecordDto
            {
                ExerciseId = r.ExerciseId,
                ExerciseName = r.ExerciseName,
                WeightKg = r.WeightKg,
                Reps = r.Reps,
                AchievedAtUtc = r.AchievedAtUtc,
                PreviousBestWeightKg = r.PreviousBestWeightKg
            }).ToList();
        });

    public Task<ServiceResult<List<TrackedExerciseDto>>> GetTrackedExercisesAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await EnsureProAsync(userId, "tracked exercises", cancellationToken);

            var exercises = await workoutSessionProvider.GetTrackedExercisesAsync(userId, cancellationToken);

            return exercises.Select(e => new TrackedExerciseDto
            {
                ExerciseId = e.ExerciseId,
                ExerciseName = e.ExerciseName,
                SessionCount = e.SessionCount,
                LastTrainedAtUtc = e.LastTrainedAtUtc
            }).ToList();
        });

    public Task<ServiceResult<ExerciseProgressDto>> GetExerciseProgressAsync(Guid userId, Guid exerciseId, int days, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await EnsureProAsync(userId, "exercise progress", cancellationToken);

            var effectiveDays = days <= 0 ? 90 : Math.Min(days, MaxExerciseProgressDays);
            var fromDate = DateTime.UtcNow.Date.AddDays(-(effectiveDays - 1));
            var points = await workoutSessionProvider.GetExerciseProgressAsync(userId, exerciseId, fromDate, cancellationToken);

            return new ExerciseProgressDto
            {
                ExerciseId = exerciseId,
                Days = effectiveDays,
                Points = points.Select(p => new ExerciseProgressPointDto
                {
                    Date = p.ScheduledDateUtc,
                    TopWeightKg = p.TopWeightKg,
                    TopSetReps = p.TopSetReps,
                    EstimatedOneRmKg = p.EstimatedOneRmKg,
                    TotalVolumeKg = p.TotalVolumeKg,
                    TotalReps = p.TotalReps,
                    SetCount = p.SetCount
                }).ToList()
            };
        });

    private async Task EnsureProAsync(Guid userId, string feature, CancellationToken cancellationToken)
    {
        if (!await subscriptionGate.HasActiveProAsync(userId, cancellationToken).ConfigureAwait(false))
        {
            throw new ProUpgradeRequiredException(
                $"User {userId} requested {feature} without an active Pro/Advanced subscription.",
                "Upgrade to Pro to track progress for each exercise.");
        }
    }
}
